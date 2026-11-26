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

run "manager_user_data_is_gzipped" {
  command = apply

  assert {
    condition     = aws_instance.runner_manager.user_data == null
    error_message = "The Manager's script goes in user_data_base64 only."
  }

  assert {
    condition     = aws_instance.runner_manager.user_data_base64 == base64gzip(local.runner_manager_user_data)
    error_message = "The Manager's user data is its first-boot script, gzipped."
  }

  assert {
    condition     = startswith(local.runner_manager_user_data, "#!/bin/bash")
    error_message = "cloud-init runs the unpacked user data as a shell script."
  }
}
