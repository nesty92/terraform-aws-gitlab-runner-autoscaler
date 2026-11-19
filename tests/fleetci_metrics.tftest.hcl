mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "us-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { default_vcpus = 4, memory_size = 8192 }
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
    ami_id      = "ami-fleetci-amd64"
    type        = "c7i.xlarge"
  }
}

run "an_unnamed_class_is_named_after_its_size" {
  command = apply

  variables {
    runner_fleetci_amd64 = {
      classes = {
        "8vcpu-16gb" = { instance_types = ["c7i.2xlarge"], ami_id = "ami-fleetci-amd64" }
      }
    }
  }

  assert {
    condition     = data.aws_ec2_instance_type.fleetci_unnamed["amd64"].instance_type == "c7i.xlarge"
    error_message = "The size is the runner's own instance type's."
  }

  assert {
    condition     = output.fleetci.amd64.default_class == "4vcpu-8gb" && output.fleetci.amd64.classes["4vcpu-8gb"].asg_name == "gitlab-runner-amd64-asg"
    error_message = "With no class, the runner's own group is the class <vCPUs>vcpu-<GiB>gb, and the default."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "default_class = \"4vcpu-8gb\"")
    error_message = "fleetci.toml names the derived class as the default."
  }
}

run "a_named_class_reads_no_instance_type" {
  command = apply

  variables {
    runner_fleetci_amd64 = { class = "medium" }
  }

  assert {
    condition     = length(data.aws_ec2_instance_type.fleetci_unnamed) == 0 && output.fleetci.amd64.default_class == "medium"
    error_message = "A class the runner names is used as it is."
  }
}

run "memory_short_of_a_whole_gib_is_named_in_mb" {
  command = apply

  override_data {
    target = data.aws_ec2_instance_type.fleetci_unnamed
    values = { default_vcpus = 2, memory_size = 512 }
  }

  variables {
    runner_fleetci_amd64 = {}
  }

  assert {
    condition     = output.fleetci.amd64.default_class == "2vcpu-512mb"
    error_message = "A size that isn't whole GiB is named in MiB."
  }
}

run "an_unnamed_class_cant_take_an_extra_class_name" {
  command = plan

  variables {
    runner_fleetci_amd64 = {
      classes = {
        "4vcpu-8gb" = { instance_types = ["c7a.xlarge"], ami_id = "ami-fleetci-amd64" }
      }
    }
  }

  expect_failures = [aws_instance.runner_manager]
}

run "without_metrics_fleetci_serves_none_and_nothing_ships" {
  command = apply

  variables {
    runner_fleetci_amd64 = { class = "4vcpu-8gb" }
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "usage_file = \"/var/lib/fleetci/amd64/usage.jsonl\"")
    error_message = "Every fleetci runner keeps its jobs' usage in a file of its own."
  }

  assert {
    condition     = !strcontains(aws_instance.runner_manager.user_data, "metrics_listen") && !strcontains(aws_instance.runner_manager.user_data, "prometheus")
    error_message = "Without runner_manager.metrics, fleetci serves no metrics and no Prometheus is installed."
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "listen_address = \"\"")
    error_message = "gitlab-runner's listen address stays as set."
  }

  assert {
    condition     = length(aws_iam_role_policy.metrics_remote_write) == 0
    error_message = "No metrics, no permissions for them."
  }

  assert {
    condition     = !strcontains(aws_instance.runner_manager.user_data, ".reclaim]")
    error_message = "fleetci's own reclaim defaults are left alone."
  }
}

run "metrics_ship_gitlab_runner_and_fleetci_to_amp" {
  command = apply

  variables {
    runner_manager = {
      metrics = {
        remote_write = {
          url           = "https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-1/api/v1/remote_write"
          sigv4_region  = "us-west-2"
          workspace_arn = "arn:aws:aps:us-west-2:111122223333:workspace/ws-1"
        }
        external_labels = { environment = "ci" }
      }
    }
    runner_fleetci_amd64 = { class = "4vcpu-8gb" }
  }

  assert {
    condition     = strcontains(aws_instance.runner_manager.user_data, "metrics_listen = \"127.0.0.1:9483\"") && strcontains(aws_instance.runner_manager.user_data, "listen_address = \"127.0.0.1:9252\"")
    error_message = "fleetci and gitlab-runner serve their metrics on 127.0.0.1."
  }

  assert {
    condition = alltrue([for s in [
      "prometheus-3.15.1.linux-amd64.tar.gz",
      "sha256sum -c",
      "--agent",
      "systemctl enable --now prometheus-agent",
    ] : strcontains(aws_instance.runner_manager.user_data, s)])
    error_message = "The Manager installs a checked Prometheus release and runs it in agent mode."
  }

  assert {
    condition = (
      yamldecode(local.prometheus_agent.config).remote_write[0].sigv4.region == "us-west-2" &&
      yamldecode(local.prometheus_agent.config).global.external_labels == { runner_manager = "gitlab-runner-manager-test", environment = "ci" } &&
      [for c in yamldecode(local.prometheus_agent.config).scrape_configs : c.job_name] == ["gitlab-runner", "prometheus-agent", "fleetci"] &&
      yamldecode(local.prometheus_agent.config).scrape_configs[2].static_configs == [{ targets = ["127.0.0.1:9483"], labels = { runner = "runner-amd64" } }]
    )
    error_message = "The agent scrapes gitlab-runner, itself and each fleetci, and signs its writes."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.metrics_remote_write[0].policy).Statement[0].Resource == "arn:aws:aps:us-west-2:111122223333:workspace/ws-1"
    error_message = "The Manager may write to the named workspace only."
  }
}

run "metrics_keep_the_addresses_set_and_need_no_signing" {
  command = apply

  variables {
    runner_manager = {
      prometheus_listen_address = "0.0.0.0:9300"
      metrics = {
        remote_write = { url = "http://prometheus.internal:9090/api/v1/write" }
      }
    }
    runner_fleetci_amd64 = { class = "4vcpu-8gb", metrics_listen = "0.0.0.0:9500" }
  }

  assert {
    condition = (
      yamldecode(local.prometheus_agent.config).scrape_configs[0].static_configs[0].targets == ["127.0.0.1:9300"] &&
      yamldecode(local.prometheus_agent.config).scrape_configs[2].static_configs[0].targets == ["127.0.0.1:9500"] &&
      !can(yamldecode(local.prometheus_agent.config).remote_write[0].sigv4)
    )
    error_message = "Addresses that are set are scraped on their ports; without sigv4_region writes go unsigned."
  }

  assert {
    condition     = length(aws_iam_role_policy.metrics_remote_write) == 0
    error_message = "No workspace, no aps:RemoteWrite."
  }
}

run "reclaim_settings_reach_every_class" {
  command = apply

  variables {
    runner_fleetci_amd64 = {
      class   = "4vcpu-8gb"
      reclaim = { rebalance = true }
      classes = {
        "8vcpu-16gb" = { instance_types = ["c7i.2xlarge"], ami_id = "ami-fleetci-amd64" }
      }
    }
  }

  assert {
    condition = alltrue([for c in ["4vcpu-8gb", "8vcpu-16gb"] :
      strcontains(aws_instance.runner_manager.user_data, "[classes.${c}.reclaim]\nwatch = true\nrebalance = true")
    ])
    error_message = "reclaim is written for each of the runner's classes."
  }
}
