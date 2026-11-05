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

run "fleetci_changes_only_the_pools_plugin" {
  command = apply

  variables {
    runner_pools = {
      ci = {
        architecture = "amd64"
        ami_id       = "ami-fleetci-amd64"
        token = {
          name   = "gitlab-runner-ci-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-ci-token"
          region = "us-west-2"
        }
        autoscaler = { max_instances = 3, capacity_per_instance = 1, max_use_count = 1 }
        fleetci = {
          class = "2vcpu-4gb"
          classes = {
            "8vcpu-16gb-arm" = {
              architecture         = "arm64"
              instance_types       = ["c7g.2xlarge", "c6g.2xlarge"]
              max_instances        = 2
              ami_id               = "ami-fleetci-arm64"
              private_address_only = false
              user_data            = "#!/bin/sh\necho extra\n"
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
    }
  }

  assert {
    condition     = keys(output.pools) == ["amd64", "ci"] && output.pools.ci.runner_name == "runner-ci"
    error_message = "fleetci adds no runner: the pool stays the pool."
  }

  assert {
    condition     = keys(aws_autoscaling_group.gitlab_runner_instance) == ["amd64", "ci", "ci-8vcpu-16gb-arm"]
    error_message = "The pool keeps its group as its own class; each extra class gets one more."
  }

  assert {
    condition     = output.fleetci.ci.default_class == "2vcpu-4gb" && output.fleetci.ci.classes["2vcpu-4gb"].asg_name == "gitlab-runner-ci-asg" && output.fleetci.ci.classes["8vcpu-16gb-arm"].asg_name == "gitlab-runner-ci-8vcpu-16gb-arm-asg" && output.fleetci.ci.classes["8vcpu-16gb-arm"].github_label == "fleetci-8vcpu-16gb-arm"
    error_message = "The fleetci output lists the pool's classes and their groups."
  }

  assert {
    condition     = aws_autoscaling_group.gitlab_runner_instance["ci-8vcpu-16gb-arm"].max_size == 2 && aws_launch_template.gitlab_runner_instance["ci-8vcpu-16gb-arm"].image_id == "ami-fleetci-arm64"
    error_message = "An extra class launches its own image, as many as its max_instances."
  }

  assert {
    condition     = one(aws_launch_template.gitlab_runner_instance["ci-8vcpu-16gb-arm"].block_device_mappings).device_name == "/dev/sda1" && one(one(aws_launch_template.gitlab_runner_instance["ci-8vcpu-16gb-arm"].block_device_mappings).ebs).volume_size == 30
    error_message = "Ubuntu's root device is /dev/sda1, 30 GiB by default."
  }

  assert {
    condition     = base64decode(aws_launch_template.gitlab_runner_instance["ci-8vcpu-16gb-arm"].user_data) == "#!/bin/sh\necho extra\n" && length(aws_autoscaling_group.gitlab_runner_instance["ci-8vcpu-16gb-arm"].mixed_instances_policy) == 1
    error_message = "A class's user_data and instance types reach its group."
  }

  assert {
    condition     = one(aws_launch_template.gitlab_runner_instance["ci-8vcpu-16gb-arm"].network_interfaces).associate_public_ip_address == "true"
    error_message = "private_address_only = false gives a class's VMs a public address."
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.ssm_read_runner_tokens.policy).Statement[0].Resource, "arn:aws:ssm:us-west-2:111122223333:parameter/fleetci-github-token")
    error_message = "The Manager may read the pool's GitHub token."
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.gitlab_runner_manager.policy).Statement[2].Condition.StringEquals["ec2:ResourceTag/aws:autoscaling:groupName"], "gitlab-runner-ci-8vcpu-16gb-arm-asg")
    error_message = "The Manager may reach an extra class's VMs through EC2 Instance Connect."
  }

  assert {
    condition = alltrue([for s in [
      "concurrent = 12",
      "capacity_per_instance = 5",
      "plugin = \"/usr/bin/fleeting-plugin-fleetci-ci\"",
      "config_file = \"/etc/fleetci/ci.toml\"",
      "image = \"class-$${FLEETCI_CLASS}\"",
      "nesting_host = \"unix:///fleetci/nesting.sock\"",
      "ln -sf /usr/bin/fleeting-plugin-fleetci /usr/bin/fleeting-plugin-fleetci-ci",
      "default_class = \"2vcpu-4gb\"",
      "[classes.2vcpu-4gb]",
      "name = \"gitlab-runner-ci-asg\"",
      "connector_config = { arch = \"amd64\", os = \"linux\", timeout = \"5m\", use_external_addr = false, use_static_credentials = false, username = \"ubuntu\" }",
      "connector_config = { arch = \"arm64\", timeout = \"5m\", username = \"ubuntu\" }",
      "name = \"gitlab-runner-ci-8vcpu-16gb-arm-asg\"",
      "[[classes.8vcpu-16gb-arm.policy]]",
      "repos = [\"owner/name\"]",
      "token_file = \"/etc/fleetci/ci-github.token\"",
      "fleetci check -config /etc/fleetci/ci.toml",
      "ExecStart=/usr/bin/fleetci watchdog -plugin /usr/bin/fleeting-plugin-fleetci-%i",
      "systemctl enable --now fleetci-watchdog@ci",
    ] : strcontains(aws_instance.runner_manager.user_data, s)])
    error_message = "The pool's runner uses fleetci's plugin, whose config, symlink, check and watchdog the Manager sets up."
  }

  assert {
    condition     = !strcontains(aws_instance.runner_manager.user_data, "runner-fleetci") && !strcontains(aws_instance.runner_manager.user_data, "fleeting-plugin-aws\"\n  [runners.autoscaler.plugin_config]\n    name = \"gitlab-runner-ci-asg\"")
    error_message = "There is no separate fleetci runner, and the pool's runner no longer drives its group with fleeting-plugin-aws."
  }

  assert {
    condition     = length(aws_instance.runner_manager.user_data) < 16384
    error_message = "EC2 refuses user data over 16 KB."
  }

  assert {
    condition     = yamldecode(output.fleetci.ci.ci_include)[".fleetci-8vcpu-16gb-arm"].variables.FLEETCI_CLASS == "8vcpu-16gb-arm" && yamldecode(output.fleetci.ci.ci_include)[".fleetci"].tags == ["fleetci"]
    error_message = "ci_include has one hidden job per class, on the fleetci tag."
  }
}

run "reuse_for_gitlab_and_github_in_another_pool" {
  command = apply

  variables {
    runner_pools = {
      reuse = {
        architecture = "amd64"
        ami_id       = "ami-fleetci-amd64"
        token = {
          name   = "gitlab-runner-reuse-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-reuse-token"
          region = "us-west-2"
        }
        fleetci = {
          class    = "2vcpu-4gb"
          watchdog = false
          classes = {
            "4vcpu-8gb" = { instance_types = ["c7a.xlarge"], ami_id = "ami-fleetci-amd64", capacity_per_instance = 2, max_use_count = 5 }
          }
        }
      }
      single = {
        architecture = "amd64"
        ami_id       = "ami-fleetci-amd64"
        token = {
          name   = "gitlab-runner-single-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-single-token"
          region = "us-west-2"
        }
        autoscaler = { max_use_count = 1 }
        fleetci = {
          class = "2vcpu-4gb"
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
    }
  }

  assert {
    condition = alltrue([for s in [
      "max_use_count = 10",
      "capacity_per_instance = 2",
      "max_use_count = 5",
      "config_file = \"/etc/fleetci/reuse.toml\"",
      "config_file = \"/etc/fleetci/single.toml\"",
      "token_file = \"/etc/fleetci/single-github.token\"",
      "systemctl enable --now fleetci-watchdog@single",
    ] : strcontains(aws_instance.runner_manager.user_data, s)])
    error_message = "Each pool runs its own fleetci; the GitLab-only one keeps reusing VMs."
  }

  assert {
    condition     = !strcontains(aws_instance.runner_manager.user_data, "fleetci-watchdog@reuse") && !strcontains(aws_instance.runner_manager.user_data, "reuse-github.token")
    error_message = "watchdog = false and no github leave those out for that pool."
  }

  assert {
    condition     = length(aws_instance.runner_manager.user_data) < 16384
    error_message = "EC2 refuses user data over 16 KB, with two fleetci pools too."
  }
}

run "github_refuses_a_pool_that_reuses_vms" {
  command = plan

  variables {
    runner_pools = {
      ci = {
        architecture = "amd64"
        ami_id       = "ami-1"
        token = {
          name   = "gitlab-runner-ci-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-ci-token"
          region = "us-west-2"
        }
        fleetci = {
          class = "2vcpu-4gb"
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
    }
  }

  expect_failures = [var.runner_pools]
}

run "github_refuses_a_class_that_reuses_vms" {
  command = plan

  variables {
    runner_pools = {
      ci = {
        architecture = "amd64"
        ami_id       = "ami-1"
        token = {
          name   = "gitlab-runner-ci-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-ci-token"
          region = "us-west-2"
        }
        autoscaler = { max_use_count = 1 }
        fleetci = {
          class   = "2vcpu-4gb"
          classes = { big = { instance_types = ["c7a.2xlarge"], ami_id = "ami-1", max_use_count = 3 } }
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
    }
  }

  expect_failures = [var.runner_pools]
}

run "fleetci_needs_docker_autoscaler" {
  command = plan

  variables {
    runner_pools = {
      ci = {
        architecture = "amd64"
        executor     = "instance"
        ami_id       = "ami-1"
        token = {
          name   = "gitlab-runner-ci-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-ci-token"
          region = "us-west-2"
        }
        fleetci = { class = "2vcpu-4gb" }
      }
    }
  }

  expect_failures = [var.runner_pools]
}

run "class_names_are_checked" {
  command = plan

  variables {
    runner_pools = {
      ci = {
        architecture = "amd64"
        ami_id       = "ami-1"
        token = {
          name   = "gitlab-runner-ci-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-ci-token"
          region = "us-west-2"
        }
        fleetci = { class = "Big_One" }
      }
    }
  }

  expect_failures = [var.runner_pools]
}

run "a_class_needs_an_instance_type" {
  command = plan

  variables {
    runner_pools = {
      ci = {
        architecture = "amd64"
        ami_id       = "ami-1"
        token = {
          name   = "gitlab-runner-ci-token"
          arn    = "arn:aws:ssm:us-west-2:111122223333:parameter/gitlab-runner-ci-token"
          region = "us-west-2"
        }
        fleetci = {
          class   = "2vcpu-4gb"
          classes = { big = { instance_types = [], ami_id = "ami-1" } }
        }
      }
    }
  }

  expect_failures = [var.runner_pools]
}
