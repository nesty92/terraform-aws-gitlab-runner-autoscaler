mock_provider "aws" {
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-ubuntu" }
  }
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

run "without_fleetci_nothing_changes" {
  command = apply

  assert {
    condition     = output.fleetci == null && keys(aws_autoscaling_group.gitlab_runner_instance) == ["amd64"]
    error_message = "Without fleetci there is no fleetci output and no class group."
  }

  assert {
    condition     = !strcontains(aws_instance.runner_manager.user_data, "fleetci")
    error_message = "Without fleetci the Manager's user data never mentions it."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.ssm_read_runner_tokens.policy).Statement[0].Resource == ["arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-amd64-token"]
    error_message = "Without fleetci the Manager reads only the runners' tokens."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "concurrent = 10")
    error_message = "Without fleetci concurrent stays at maximum_concurrent_jobs."
  }
}

run "classes_get_groups_a_runner_and_an_include" {
  command = apply

  variables {
    fleetci = {
      token = {
        name   = "fleetci-token"
        arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/fleetci-token"
        region = "us-west-2"
      }
      default_class = "2vcpu-4gb"
      classes = {
        "2vcpu-4gb" = {
          instance_types = ["t3.medium"]
        }
        "8vcpu-16gb-arm" = {
          architecture   = "arm64"
          instance_types = ["c7g.2xlarge", "c6g.2xlarge"]
          max_instances  = 2
          ami_id         = "ami-arm"
          policy = [{
            periods    = ["* 8-18 * * mon-fri"]
            timezone   = "Europe/Warsaw"
            idle_count = 1
          }]
        }
      }
      github = {
        repos = ["owner/name"]
        token = {
          name   = "fleetci-github-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/fleetci-github-token"
          region = "us-west-2"
        }
      }
    }
  }

  assert {
    condition     = keys(output.pools) == ["amd64"]
    error_message = "fleetci's classes are not runner pools."
  }

  assert {
    condition     = keys(output.fleetci.classes) == ["2vcpu-4gb", "8vcpu-16gb-arm"]
    error_message = "Each class is listed in the fleetci output."
  }

  assert {
    condition     = aws_autoscaling_group.gitlab_runner_instance["fleetci-2vcpu-4gb"].name == "gitlab-runner-fleetci-2vcpu-4gb-asg" && aws_autoscaling_group.gitlab_runner_instance["fleetci-2vcpu-4gb"].max_size == 4 && aws_autoscaling_group.gitlab_runner_instance["fleetci-8vcpu-16gb-arm"].max_size == 2
    error_message = "Each class has its own group, as large as its max_instances."
  }

  assert {
    condition     = aws_launch_template.gitlab_runner_instance["fleetci-2vcpu-4gb"].image_id == "ami-ubuntu" && aws_launch_template.gitlab_runner_instance["fleetci-8vcpu-16gb-arm"].image_id == "ami-arm"
    error_message = "A class without ami_id runs Ubuntu 24.04; ami_id overrides it."
  }

  assert {
    condition     = one(aws_launch_template.gitlab_runner_instance["fleetci-2vcpu-4gb"].block_device_mappings).device_name == "/dev/sda1" && one(one(aws_launch_template.gitlab_runner_instance["fleetci-2vcpu-4gb"].block_device_mappings).ebs).volume_size == 30
    error_message = "Ubuntu's root device is /dev/sda1, 30 GiB by default."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.gitlab_runner_instance["fleetci-8vcpu-16gb-arm"].user_data), "actions-runner-linux-arm64-2.338.2") && strcontains(base64decode(aws_launch_template.gitlab_runner_instance["fleetci-2vcpu-4gb"].user_data), "actions-runner-linux-x64-2.338.2")
    error_message = "Each class VM unpacks actions/runner for its architecture."
  }

  assert {
    condition     = length(aws_autoscaling_group.gitlab_runner_instance["fleetci-8vcpu-16gb-arm"].mixed_instances_policy) == 1 && length(aws_autoscaling_group.gitlab_runner_instance["fleetci-2vcpu-4gb"].mixed_instances_policy) == 0
    error_message = "A class with several instance types has a mixed instances policy; one type keeps a plain template."
  }

  assert {
    condition = alltrue([for arn in [
      "arn:aws:ssm:us-west-2:111122223333:parameter/fleetci-token",
      "arn:aws:ssm:us-west-2:111122223333:parameter/fleetci-github-token",
    ] : contains(jsondecode(aws_iam_role_policy.ssm_read_runner_tokens.policy).Statement[0].Resource, arn)])
    error_message = "The Manager may read fleetci's runner token and its GitHub token."
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.gitlab_runner_manager.policy).Statement[2].Condition.StringEquals["ec2:ResourceTag/aws:autoscaling:groupName"], "gitlab-runner-fleetci-2vcpu-4gb-asg")
    error_message = "The Manager may reach the class VMs through EC2 Instance Connect."
  }

  assert {
    condition = alltrue([for s in [
      "concurrent = 16",
      "capacity_per_instance = 6",
      "image = \"class-$${FLEETCI_CLASS}\"",
      "config_file = \"/etc/fleetci/fleetci.toml\"",
      "[runners.autoscaler.vm_isolation.connector_config]",
      "name = \"gitlab-runner-fleetci-8vcpu-16gb-arm-asg\"",
      "[[classes.8vcpu-16gb-arm.policy]]",
      "repos = [\"owner/name\"]",
      "fleetci-github-token",
      "fleetci check",
    ] : strcontains(aws_instance.runner_manager.user_data, s)])
    error_message = "The Manager installs fleetci, writes fleetci.toml and its runner, and runs fleetci check."
  }

  assert {
    condition     = length(aws_instance.runner_manager.user_data) < 16384
    error_message = "EC2 refuses user data over 16 KB."
  }

  assert {
    condition     = yamldecode(output.fleetci.ci_include)[".fleetci-8vcpu-16gb-arm"].variables.FLEETCI_CLASS == "8vcpu-16gb-arm" && yamldecode(output.fleetci.ci_include)[".fleetci"].tags == ["fleetci"]
    error_message = "ci_include has one hidden job per class, on the fleetci tag."
  }
}

run "default_class_must_be_a_class" {
  command = plan

  variables {
    fleetci = {
      token         = { name = "t", arn = "arn:aws:ssm:us-west-2:111122223333:parameter/t", region = "us-west-2" }
      default_class = "huge"
      classes       = { "2vcpu-4gb" = { instance_types = ["t3.medium"] } }
    }
  }

  expect_failures = [var.fleetci]
}

run "class_names_are_checked" {
  command = plan

  variables {
    fleetci = {
      token         = { name = "t", arn = "arn:aws:ssm:us-west-2:111122223333:parameter/t", region = "us-west-2" }
      default_class = "Big_One"
      classes       = { "Big_One" = { instance_types = ["t3.medium"] } }
    }
  }

  expect_failures = [var.fleetci]
}

run "a_class_needs_an_instance_type" {
  command = plan

  variables {
    fleetci = {
      token         = { name = "t", arn = "arn:aws:ssm:us-west-2:111122223333:parameter/t", region = "us-west-2" }
      default_class = "2vcpu-4gb"
      classes       = { "2vcpu-4gb" = { instance_types = [] } }
    }
  }

  expect_failures = [var.fleetci]
}
