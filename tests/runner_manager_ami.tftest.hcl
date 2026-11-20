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

run "latest_amazon_linux_2_by_default" {
  command = plan

  override_data {
    target = data.aws_ami.amazon_linux_2
    values = { id = "ami-latest" }
  }

  assert {
    condition     = aws_instance.runner_manager.ami == "ami-latest"
    error_message = "With no ami_id the Manager boots the latest Amazon Linux 2 AMI."
  }
}

run "pinned_ami" {
  command = plan

  variables {
    runner_manager = {
      ami_id = "ami-pinned"
    }
  }

  assert {
    condition     = aws_instance.runner_manager.ami == "ami-pinned"
    error_message = "A pinned ami_id is the AMI the Manager boots from."
  }

  assert {
    condition     = length(data.aws_ami.amazon_linux_2) == 0
    error_message = "With a pinned ami_id the latest AMI is not looked up."
  }
}
