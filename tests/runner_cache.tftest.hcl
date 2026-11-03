mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "us-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_resource "aws_autoscaling_group" {
    defaults = { arn = "arn:aws:autoscaling:us-west-2:111122223333:autoScalingGroup:x" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/r" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::111122223333:instance-profile/p" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1, arn = "arn:aws:ec2:us-west-2:111122223333:launch-template/lt" }
  }
  mock_resource "aws_instance" {
    defaults = { arn = "arn:aws:ec2:us-west-2:111122223333:instance/i" }
  }
}

variables {
  fleeting_plugin_aws_version = "1.0.0"
  gitlab_runner_version       = "18.5.0"
  aws_vpc_id                  = "vpc-1"
  aws_subnet_ids              = ["subnet-a"]
  architectures               = ["amd64"]
  environment                 = "test"
  runner_ssm_token_amd64 = {
    name   = "gitlab-runner-amd64-token"
    arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-amd64-token"
    region = "us-west-2"
  }
  runner_instance_amd64 = {
    name_prefix = "gitlab-runner-amd64"
    ami_id      = "ami-amd64"
  }
}

run "no_cache_by_default" {
  command = apply

  assert {
    condition     = !strcontains(aws_instance.runner_manager.user_data, "[runners.cache]")
    error_message = "Without runner_cache the runners keep their local cache only."
  }

  assert {
    condition     = length(aws_iam_role_policy.runner_cache) == 0
    error_message = "Without runner_cache the Manager is granted no bucket."
  }
}

run "every_runner_shares_the_cache" {
  command = apply

  variables {
    runner_cache = {
      path                      = "/jobs/"
      max_uploaded_archive_size = 2147483648
      s3 = {
        bucket_name = "example-runner-cache"
        dual_stack  = false
      }
    }
    runner_pools = {
      e2e = {
        architecture = "amd64"
        executor     = "instance"
        ami_id       = "ami-machine"
        token = {
          name   = "gitlab-runner-e2e-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-e2e-token"
          region = "us-west-2"
        }
      }
    }
  }

  assert {
    condition = length(regexall(
      "\\[runners\\.cache\\]\\s+Type = \"s3\"\\s+Path = \"jobs\"\\s+Shared = true\\s+MaxUploadedArchiveSize = 2147483648\\s+\\[runners\\.cache\\.s3\\]\\s+BucketName = \"example-runner-cache\"\\s+BucketLocation = \"us-west-2\"\\s+AuthenticationType = \"iam\"\\s+DualStack = false\\s",
      aws_instance.runner_manager.user_data,
    )) == 2
    error_message = "Both the per-architecture runner and the instance pool share one S3 cache, in the module's region, signed with the Manager's role."
  }

  assert {
    condition     = !strcontains(aws_instance.runner_manager.user_data, "ServerSideEncryption")
    error_message = "With no encryption asked for, the bucket's default applies."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.runner_cache[0].policy).Statement == [
      {
        Sid      = "ReadAndWriteTheJobsCaches"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::example-runner-cache/jobs/*"
      },
      {
        Sid       = "TellAMissingCacheFromARefusedOne"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::example-runner-cache"
        Condition = { StringLike = { "s3:prefix" = ["jobs/*"] } }
      },
    ]
    error_message = "The Manager may read and write the caches under the path, and list only under it, and nothing else."
  }
}

run "a_kms_encrypted_cache" {
  command = apply

  variables {
    runner_cache = {
      shared = false
      s3 = {
        bucket_name                   = "example-runner-cache"
        bucket_region                 = "eu-west-1"
        server_side_encryption        = "KMS"
        server_side_encryption_key_id = "arn:aws:kms:eu-west-1:111122223333:key/abc"
      }
    }
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "Shared = false")
    error_message = "A cache asked not to be shared is one per runner."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "BucketLocation = \"eu-west-1\"")
    error_message = "The bucket's own region wins over the module's."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "ServerSideEncryption = \"KMS\"") && strcontains(aws_instance.runner_manager.user_data, "ServerSideEncryptionKeyID = \"arn:aws:kms:eu-west-1:111122223333:key/abc\"")
    error_message = "The runner encrypts each cache with the key it is given."
  }

  assert {
    condition     = !strcontains(aws_instance.runner_manager.user_data, "Path =") && !strcontains(aws_instance.runner_manager.user_data, "DualStack")
    error_message = "An empty path and an unset dual_stack leave the runner's defaults."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.runner_cache[0].policy).Statement == [
      {
        Sid      = "ReadAndWriteTheJobsCaches"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::example-runner-cache/*"
      },
      {
        Sid      = "TellAMissingCacheFromARefusedOne"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::example-runner-cache"
      },
      {
        Sid      = "EncryptTheJobsCaches"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = "arn:aws:kms:eu-west-1:111122223333:key/abc"
      },
    ]
    error_message = "With a KMS key the Manager may use it, and only it."
  }
}

run "a_bucket_must_be_named" {
  command = plan

  variables {
    runner_cache = {
      s3 = {
        bucket_name = " "
      }
    }
  }

  expect_failures = [var.runner_cache]
}

run "the_archive_limit_is_whole_bytes" {
  command = plan

  variables {
    runner_cache = {
      max_uploaded_archive_size = -1
      s3 = {
        bucket_name = "example-runner-cache"
      }
    }
  }

  expect_failures = [var.runner_cache]
}

run "encryption_is_one_the_runner_knows" {
  command = plan

  variables {
    runner_cache = {
      s3 = {
        bucket_name            = "example-runner-cache"
        server_side_encryption = "AES256"
      }
    }
  }

  expect_failures = [var.runner_cache]
}

run "a_kms_key_needs_kms_encryption" {
  command = plan

  variables {
    runner_cache = {
      s3 = {
        bucket_name                   = "example-runner-cache"
        server_side_encryption        = "S3"
        server_side_encryption_key_id = "arn:aws:kms:us-west-2:111122223333:key/abc"
      }
    }
  }

  expect_failures = [var.runner_cache]
}

run "kms_encryption_needs_a_key" {
  command = plan

  variables {
    runner_cache = {
      s3 = {
        bucket_name            = "example-runner-cache"
        server_side_encryption = "KMS"
      }
    }
  }

  expect_failures = [var.runner_cache]
}
