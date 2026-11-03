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
  aws_subnet_ids              = ["subnet-private-a", "subnet-private-b"]
  architectures               = ["amd64", "arm64"]
  environment                 = "test"
  runner_ssm_token_amd64 = {
    name   = "gitlab-runner-amd64-token"
    arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-amd64-token"
    region = "us-west-2"
  }
  runner_ssm_token_arm64 = {
    name   = "gitlab-runner-arm64-token"
    arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-arm64-token"
    region = "us-west-2"
  }
  runner_instance_amd64 = {
    name_prefix = "gitlab-runner-amd64"
    ami_id      = "ami-amd64"
  }
  runner_instance_arm64 = {
    name_prefix = "gitlab-runner-arm64"
    ami_id      = "ami-arm64"
  }
}

run "runners_use_the_module_subnets_by_default" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.gitlab_runner_instance["amd64"].vpc_zone_identifier == toset(["subnet-private-a", "subnet-private-b"])
    error_message = "Without subnet_ids the amd64 runners launch into aws_subnet_ids, as before."
  }

  assert {
    condition     = aws_autoscaling_group.gitlab_runner_instance["arm64"].vpc_zone_identifier == toset(["subnet-private-a", "subnet-private-b"])
    error_message = "Without subnet_ids the arm64 runners launch into aws_subnet_ids, as before."
  }

  assert {
    condition     = aws_instance.runner_manager.subnet_id == "subnet-private-a"
    error_message = "The Manager stays in the first of aws_subnet_ids."
  }
}

run "an_architecture_launches_into_its_own_subnets" {
  command = plan

  variables {
    runner_instance_amd64 = {
      name_prefix          = "gitlab-runner-amd64"
      ami_id               = "ami-amd64"
      private_address_only = false
      subnet_ids           = ["subnet-public-a", "subnet-public-b"]
    }
  }

  assert {
    condition     = aws_autoscaling_group.gitlab_runner_instance["amd64"].vpc_zone_identifier == toset(["subnet-public-a", "subnet-public-b"])
    error_message = "subnet_ids moves the amd64 runners to those subnets."
  }

  assert {
    condition     = aws_autoscaling_group.gitlab_runner_instance["arm64"].vpc_zone_identifier == toset(["subnet-private-a", "subnet-private-b"])
    error_message = "An architecture with no subnet_ids is left on aws_subnet_ids."
  }

  assert {
    condition     = aws_instance.runner_manager.subnet_id == "subnet-private-a"
    error_message = "The Manager does not move with the runners."
  }
}

run "subnet_ids_name_a_subnet" {
  command = plan

  variables {
    runner_instance_amd64 = {
      ami_id     = "ami-amd64"
      subnet_ids = []
    }
  }

  expect_failures = [var.runner_instance_amd64]
}
