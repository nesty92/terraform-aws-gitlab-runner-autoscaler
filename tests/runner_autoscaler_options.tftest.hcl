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

run "partial_options_keep_the_documented_defaults" {
  command = apply

  variables {
    runner_autoscaler_options_amd64 = { max_use_count = 1 }
  }

  assert {
    condition     = aws_autoscaling_group.gitlab_runner_instance["amd64"].max_size == 2
    error_message = "max_instances keeps its default of 2 when only max_use_count is set."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "capacity_per_instance = 1\n      max_instances = 2\n      max_use_count = 1\n")
    error_message = "The runner gets the given max_use_count and the defaults for the rest."
  }
}

run "omitted_max_use_count_is_10_not_unlimited" {
  command = apply

  variables {
    runner_autoscaler_options_amd64 = { max_instances = 5 }
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "max_instances = 5\n      max_use_count = 10\n")
    error_message = "An omitted max_use_count is the documented 10, not gitlab-runner's unlimited."
  }
}
