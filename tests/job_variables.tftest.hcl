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

run "job_variables_reach_every_runner" {
  command = apply

  variables {
    job_variables = {
      DOCKER_HUB_CACHE = "111122223333.dkr.ecr.us-west-2.amazonaws.com/docker-hub"
      CI_IMAGES        = "111122223333.dkr.ecr.us-west-2.amazonaws.com/ci"
    }
    runner_pools = {
      lanebot-e2e = {
        architecture = "amd64"
        executor     = "instance"
        ami_id       = "ami-machine"
        token = {
          name   = "gitlab-runner-lanebot-e2e-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-lanebot-e2e-token"
          region = "us-west-2"
        }
      }
    }
  }

  assert {
    condition = length(regexall(
      "environment = \\[\"CI_IMAGES=111122223333.dkr.ecr.us-west-2.amazonaws.com/ci\",\"DOCKER_HUB_CACHE=111122223333.dkr.ecr.us-west-2.amazonaws.com/docker-hub\"\\]",
      aws_instance.runner_manager.user_data,
    )) == 2
    error_message = "Both the per-architecture runner and the instance pool set the job variables, and nothing else, with no ecr_job_images."
  }
}

run "job_variables_follow_the_credential_helper" {
  command = apply

  variables {
    ecr_job_images = {
      repository_arns = ["arn:aws:ecr:us-west-2:111122223333:repository/ci/*"]
    }
    job_variables = {
      CI_IMAGES = "111122223333.dkr.ecr.us-west-2.amazonaws.com/ci"
    }
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "environment = [\"DOCKER_AUTH_CONFIG={\\\"credHelpers\\\":{\\\"111122223333.dkr.ecr.us-west-2.amazonaws.com\\\":\\\"ecr-login\\\"}}\",\"CI_IMAGES=111122223333.dkr.ecr.us-west-2.amazonaws.com/ci\"]")
    error_message = "A docker-autoscaler runner gets the credential helper and the job variables in one environment."
  }
}

run "job_variables_cannot_replace_the_credential_helper" {
  command = plan

  variables {
    job_variables = {
      DOCKER_AUTH_CONFIG = "{}"
    }
  }

  expect_failures = [var.job_variables]
}

run "job_variables_keys_are_variable_names" {
  command = plan

  variables {
    job_variables = {
      "DOCKER-HUB" = "x"
    }
  }

  expect_failures = [var.job_variables]
}
