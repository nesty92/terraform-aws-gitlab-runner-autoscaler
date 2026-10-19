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

run "no_pools_keeps_only_the_architecture_runners" {
  command = apply

  assert {
    condition     = keys(output.pools) == ["amd64"]
    error_message = "With no runner_pools, only the per-architecture runner exists."
  }

  assert {
    condition     = !strcontains(aws_instance.runner_manager.user_data, "Runner pool")
    error_message = "With no runner_pools, the Manager's user data carries no pool."
  }
}

run "an_instance_pool_is_single_use_root_and_has_its_own_group" {
  command = apply

  variables {
    runner_pools = {
      lanebot-e2e = {
        architecture = "amd64"
        executor     = "instance"
        ami_id       = "ami-machine"
        privileged   = true
        token = {
          name   = "gitlab-runner-lanebot-e2e-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-lanebot-e2e-token"
          region = "us-west-2"
        }
        instance = {
          type       = "m8id.xlarge"
          user_data  = "#!/bin/sh\necho ready\n"
          subnet_ids = ["subnet-e2e"]
        }
        autoscaler = {
          max_instances = 4
        }
      }
    }
  }

  assert {
    condition     = keys(output.pools) == ["amd64", "lanebot-e2e"]
    error_message = "The pool is listed after the per-architecture runner."
  }

  assert {
    condition     = aws_launch_template.gitlab_runner_instance["lanebot-e2e"].image_id == "ami-machine"
    error_message = "The pool's launch template boots the pool's AMI."
  }

  assert {
    condition     = aws_launch_template.gitlab_runner_instance["lanebot-e2e"].name == "gitlab-runner-lanebot-e2e"
    error_message = "The pool's launch template is named after its key when no name_prefix is given."
  }

  assert {
    condition     = base64decode(aws_launch_template.gitlab_runner_instance["lanebot-e2e"].user_data) == "#!/bin/sh\necho ready\n"
    error_message = "The pool's user data is put on its launch template as given."
  }

  assert {
    condition     = aws_launch_template.gitlab_runner_instance["amd64"].user_data == null
    error_message = "The per-architecture launch template keeps carrying no user data."
  }

  assert {
    condition     = aws_autoscaling_group.gitlab_runner_instance["lanebot-e2e"].name == "gitlab-runner-lanebot-e2e-asg"
    error_message = "The pool has its own Auto Scaling group."
  }

  assert {
    condition     = aws_autoscaling_group.gitlab_runner_instance["lanebot-e2e"].max_size == 4
    error_message = "The pool's group is sized by its max_instances."
  }

  assert {
    condition     = sort(aws_autoscaling_group.gitlab_runner_instance["lanebot-e2e"].vpc_zone_identifier) == sort(["subnet-e2e"])
    error_message = "The pool's group uses the pool's subnets."
  }

  assert {
    condition     = aws_autoscaling_group.gitlab_runner_instance["lanebot-e2e"].protect_from_scale_in
    error_message = "The pool's group protects its instances from scale-in like every runner group."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "executor = \"instance\"")
    error_message = "The pool's runner uses the instance executor."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "max_use_count = 1")
    error_message = "An instance pool is single-use by default."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "username = \"root\"")
    error_message = "A privileged instance pool connects as root."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "token = \"__RUNNER_TOKEN_LANEBOT_E2E__\"")
    error_message = "The pool's token is a fixed placeholder in its config."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "leaving it out of config.toml")
    error_message = "A pool skips itself on an invalid token by default."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.gitlab_runner_manager.policy, "gitlab-runner-lanebot-e2e-asg")
    error_message = "The Manager may connect to the pool's instances."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.ssm_read_runner_tokens.policy, "gitlab-runner-lanebot-e2e-token")
    error_message = "The Manager may read the pool's token."
  }
}

run "a_privileged_docker_pool_sets_privileged_and_can_fail_on_a_bad_token" {
  command = apply

  variables {
    runner_pools = {
      isolated-docker = {
        architecture     = "amd64"
        ami_id           = "ami-amd64"
        privileged       = true
        on_invalid_token = "fail"
        token = {
          name   = "gitlab-runner-isolated-docker-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-isolated-docker-token"
          region = "us-west-2"
        }
        docker = {
          allowed_privileged_images = ["docker:29-dind"]
        }
      }
    }
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "privileged = true")
    error_message = "A privileged docker pool runs its containers privileged."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "allowed_privileged_images = [\"docker:29-dind\"]")
    error_message = "The pool's docker options reach [runners.docker]."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "max_use_count = 10")
    error_message = "A docker pool keeps the per-architecture reuse default."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "Invalid token for runner pool isolated-docker\"\n    exit 1")
    error_message = "on_invalid_token = fail exits the Manager's boot."
  }
}

run "a_pool_named_after_an_architecture_is_refused" {
  command = plan

  variables {
    runner_pools = {
      amd64 = {
        architecture = "amd64"
        ami_id       = "ami-amd64"
        token = {
          name   = "gitlab-runner-x-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-x-token"
          region = "us-west-2"
        }
      }
    }
  }

  expect_failures = [var.runner_pools]
}

run "docker_options_on_an_instance_pool_are_refused" {
  command = plan

  variables {
    runner_pools = {
      e2e = {
        architecture = "amd64"
        executor     = "instance"
        ami_id       = "ami-machine"
        docker       = { privileged = true }
        token = {
          name   = "gitlab-runner-e2e-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-e2e-token"
          region = "us-west-2"
        }
      }
    }
  }

  expect_failures = [var.runner_pools]
}

run "a_pool_sharing_a_token_parameter_is_refused" {
  command = plan

  variables {
    runner_pools = {
      e2e = {
        architecture = "amd64"
        ami_id       = "ami-amd64"
        token = {
          name   = "gitlab-runner-amd64-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-amd64-token"
          region = "us-west-2"
        }
      }
    }
  }

  expect_failures = [var.runner_pools]
}
