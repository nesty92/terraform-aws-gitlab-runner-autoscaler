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

run "without_ecr_job_images_nothing_changes" {
  command = apply

  assert {
    condition     = !strcontains(aws_instance.runner_manager.user_data, "ecr-login")
    error_message = "Without ecr_job_images, the Manager neither installs the ECR credential helper nor points a runner at it."
  }

  assert {
    condition     = length(aws_iam_role_policy.ecr_job_images) == 0
    error_message = "Without ecr_job_images, the Manager is given no ECR access."
  }
}

run "ecr_job_images_signs_pulls_with_the_managers_role" {
  command = apply

  variables {
    ecr_job_images = {
      repository_arns         = ["arn:aws:ecr:us-west-2:111122223333:repository/ci/*"]
      pull_through_cache_arns = ["arn:aws:ecr:us-west-2:111122223333:repository/docker-hub/*"]
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
    condition     = strcontains(aws_instance.runner_manager.user_data, "amazon-ecr-credential-helper")
    error_message = "The Manager installs the ECR credential helper."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "environment = [\"DOCKER_AUTH_CONFIG={\\\"credHelpers\\\":{\\\"111122223333.dkr.ecr.us-west-2.amazonaws.com\\\":\\\"ecr-login\\\"}}\"]")
    error_message = "The per-architecture runner resolves this account's ECR registry through the credential helper."
  }

  assert {
    condition     = length(regexall("DOCKER_AUTH_CONFIG", aws_instance.runner_manager.user_data)) == 1
    error_message = "An instance pool pulls no job images, so only the docker-autoscaler runner gets the setting."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.ecr_job_images[0].policy).Statement == [
      {
        Sid      = "LogInToTheRegistry"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PullJobImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = [
          "arn:aws:ecr:us-west-2:111122223333:repository/ci/*",
          "arn:aws:ecr:us-west-2:111122223333:repository/docker-hub/*",
        ]
      },
      {
        Sid    = "FillThePullThroughCache"
        Effect = "Allow"
        Action = [
          "ecr:BatchImportUpstreamImage",
          "ecr:CreateRepository",
          "ecr:TagResource",
        ]
        Resource = ["arn:aws:ecr:us-west-2:111122223333:repository/docker-hub/*"]
      },
    ]
    error_message = "The Manager may pull from every listed repository and fill only the pull-through cache."
  }
}

run "ecr_job_images_without_a_cache_grants_no_import" {
  command = apply

  variables {
    ecr_job_images = {
      repository_arns = ["arn:aws:ecr:us-west-2:111122223333:repository/ci/*"]
    }
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.ecr_job_images[0].policy).Statement) == 2
    error_message = "With no pull-through cache, the Manager can only log in and pull."
  }
}
