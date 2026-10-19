# Every rule of both security groups is a standalone resource, never an inline
# block: the manager's egress names the runner group and the runner's ingress
# names the manager group, which inline blocks cannot express without a cycle,
# and the provider does not allow inline and standalone rules on one group.
resource "aws_security_group" "runner" {
  name_prefix = "gitlab-runner"
  description = "Security group for GitLab Runner instances"
  vpc_id      = var.aws_vpc_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "runner_from_manager" {
  #checkov:skip=CKV_AWS_24:The source is the Runner Manager's security group, not 0.0.0.0/0; the check reads a rule without cidr_ipv4 as open to the world.
  for_each = local.runner_manager_to_runner_ports

  security_group_id            = aws_security_group.runner.id
  description                  = "Allow ${each.key} access from the Runner Manager"
  ip_protocol                  = "tcp"
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  referenced_security_group_id = aws_security_group.runner_manager.id

  tags = local.tags
}

# trivy:ignore:AVD-AWS-0104 Runners execute arbitrary CI jobs and require broad outbound access (container registries, package mirrors, user-defined endpoints).
resource "aws_vpc_security_group_egress_rule" "runner" {
  #checkov:skip=CKV_AWS_382:Runners execute arbitrary CI jobs and require broad outbound access; consumers should restrict via VPC endpoints/NACLs if needed.
  security_group_id = aws_security_group.runner.id
  description       = "Allow all outbound traffic for CI workloads"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.tags
}

resource "aws_security_group" "runner_manager" {
  name_prefix = "gitlab-runner-manager"
  description = "Security group for the GitLab Runner Manager instance"
  vpc_id      = var.aws_vpc_id

  tags = local.tags
}

# The docker-autoscaler executor drives every Runner instance over SSH (and
# WinRM for Windows) at its private address: the runner group admits the
# manager, and the manager must be let out to the runner group.
resource "aws_vpc_security_group_egress_rule" "runner_manager_to_runner" {
  for_each = local.runner_manager_to_runner_ports

  security_group_id            = aws_security_group.runner_manager.id
  description                  = "Allow ${each.key} to the Runner instances"
  ip_protocol                  = "tcp"
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  referenced_security_group_id = aws_security_group.runner.id

  tags = local.tags
}

# trivy:ignore:AVD-AWS-0104 Manager must reach GitLab, AWS API endpoints and the Amazon Linux package repositories on the public internet; egress is port-restricted to HTTP, HTTPS and DNS.
resource "aws_vpc_security_group_egress_rule" "runner_manager_to_internet" {
  for_each = {
    # Amazon Linux 2 serves its yum repositories over HTTP, and the user data
    # installs jq and gitlab-runner from them before anything else runs.
    http  = { description = "Allow HTTP to the Amazon Linux package repositories", ip_protocol = "tcp", port = 80 }
    https = { description = "Allow HTTPS to GitLab and AWS API endpoints", ip_protocol = "tcp", port = 443 }
    dns   = { description = "Allow DNS resolution", ip_protocol = "udp", port = 53 }
  }

  security_group_id = aws_security_group.runner_manager.id
  description       = each.value.description
  ip_protocol       = each.value.ip_protocol
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.tags
}

resource "aws_iam_role" "runner_manager" {
  name = format("gitlab-runner-manager-%s", var.environment)
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "ssm_read_runner_tokens" {
  name = "ssm-read-runner-tokens"
  role = aws_iam_role.runner_manager.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "ssm:GetParameters",
        Resource = [
          for key in local.pool_order : local.pool_tokens[key].arn if local.pool_tokens[key] != null
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "gitlab_runner_manager" {
  name = "gitlab-runner-manager"
  role = aws_iam_role.runner_manager.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ],
        Resource = [for key in local.pool_order : aws_autoscaling_group.gitlab_runner_instance[key].arn]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeSpotInstanceRequests"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:GetPasswordData",
          "ec2-instance-connect:SendSSHPublicKey"
        ],
        "Resource" : "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/aws:autoscaling:groupName" : [for key in local.pool_order : aws_autoscaling_group.gitlab_runner_instance[key].name]
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "runner_manager" {
  name = format("gitlab-runner-manager-%s", var.environment)
  role = aws_iam_role.runner_manager.name

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "runner_manager_ssm_managed_instance_core" {
  role       = aws_iam_role.runner_manager.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


resource "aws_instance" "runner_manager" {
  ami                  = data.aws_ami.amazon_linux_2.id
  instance_type        = var.runner_manager_instance_type
  iam_instance_profile = aws_iam_instance_profile.runner_manager.name

  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = true

  vpc_security_group_ids = [aws_security_group.runner_manager.id]

  subnet_id = var.aws_subnet_ids[0]

  root_block_device {
    encrypted = true
  }

  user_data = templatefile("${path.module}/templates/runner_manager_user_data.tftpl", {
    aws_region         = data.aws_region.current.name,
    runners_config     = local.template_runner_config
    runners_gitlab_url = var.gitlab_instance_url
    runner_tokens      = { for arch in var.architectures : arch => local.runner_tokens[arch] if local.runner_tokens[arch] != null }
    runner_pools = [
      for key in local.pool_keys : {
        key              = key
        token            = var.runner_pools[key].token
        placeholder      = local.pool_token_placeholders[key]
        on_invalid_token = var.runner_pools[key].on_invalid_token
        config           = local.pool_runner_configs[key]
      }
    ]

    fleeting_plugin_aws_version = var.fleeting_plugin_aws_version
    gitlab_runner_version       = var.gitlab_runner_version
    enable_ssm_agent            = var.runner_manager.enable_ssm_agent
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(
    local.tags,
    {
      Name = format("gitlab-runner-manager-%s", var.environment)
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "gitlab_runner_instance" {
  for_each = toset(local.pool_order)

  name = local.pool_instances[each.key].name_prefix

  image_id               = local.pool_instances[each.key].ami_id
  instance_type          = local.pool_instances[each.key].type
  update_default_version = true
  ebs_optimized          = local.pool_instances[each.key].ebs_optimized
  user_data              = lookup(local.pool_user_data, each.key, null)

  monitoring {
    enabled = local.pool_instances[each.key].monitoring
  }

  # AWS refuses a launch template that requests spot itself as the template of
  # a mixed instances policy, so with overrides the group's instances
  # distribution asks for spot instead.
  dynamic "instance_market_options" {
    for_each = length(local.runner_instance_type_overrides[each.key]) == 0 ? [0] : []
    content {
      market_type = "spot"
      dynamic "spot_options" {
        for_each = local.runner_spot_max_price[each.key] == null ? [] : [0]
        content {
          max_price = local.runner_spot_max_price[each.key]
        }
      }
    }
  }

  dynamic "iam_instance_profile" {
    for_each = local.pool_instances[each.key].iam_instance_profile == null ? [] : [0]
    content {
      name = local.pool_instances[each.key].iam_instance_profile
    }
  }

  dynamic "block_device_mappings" {
    for_each = [local.pool_instances[each.key].block_device_mappings]
    content {
      device_name = lookup(block_device_mappings.value, "device_name", "/dev/xvda")
      ebs {
        delete_on_termination = lookup(block_device_mappings.value, "delete_on_termination", true)
        volume_type           = lookup(block_device_mappings.value, "volume_type", "gp3")
        volume_size           = lookup(block_device_mappings.value, "volume_size", 8)
        encrypted             = lookup(block_device_mappings.value, "encrypted", true)
        iops                  = lookup(block_device_mappings.value, "iops", null)
        throughput            = lookup(block_device_mappings.value, "throughput", null)
        kms_key_id            = lookup(block_device_mappings.value, "kms_key_id", null)
      }
    }
  }

  network_interfaces {
    security_groups             = concat([aws_security_group.runner.id], local.pool_instances[each.key].security_group_ids)
    associate_public_ip_address = local.pool_instances[each.key].private_address_only == false
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.tags,
      local.pool_instances[each.key].additional_tags,
      # overwrites the `Name` key from `local.tags`
      local.pool_instances[each.key].name_prefix == "" ? { Name = substr(format("%s", var.environment), 0, 16) } : { Name = local.pool_instances[each.key].name_prefix },
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }

  dynamic "tag_specifications" {
    # Spot requests are the template's own only when it asks for spot itself;
    # under a mixed instances policy the group's fleet makes them instead.
    for_each = length(local.runner_instance_type_overrides[each.key]) > 0 || local.pool_instances[each.key].spot_price == null || local.pool_instances[each.key].spot_price == "" ? [] : ["spot"]
    content {
      resource_type = "spot-instances-request"
      tags          = local.tags
    }
  }

  dynamic "cpu_options" {
    for_each = local.pool_instances[each.key].cpu_options == null ? [] : [local.pool_instances[each.key].cpu_options]

    content {
      core_count            = try(cpu_options.value.core_count, null)
      threads_per_core      = try(cpu_options.value.threads_per_core, null)
      amd_sev_snp           = try(cpu_options.value.amd_sev_snp, null)
      nested_virtualization = try(cpu_options.value.nested_virtualization, null)
    }
  }



  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "gitlab_runner_instance" {
  for_each = aws_launch_template.gitlab_runner_instance

  name                      = format("gitlab-runner-%s-asg", each.key)
  vpc_zone_identifier       = lookup(local.pool_subnet_ids, each.key, var.aws_subnet_ids)
  min_size                  = 0
  max_size                  = local.pool_autoscaler_options[each.key].max_instances
  desired_capacity          = 0
  health_check_grace_period = 0
  max_instance_lifetime     = local.pool_instances[each.key].max_lifetime_seconds
  enabled_metrics           = local.pool_instances[each.key].collect_autoscaling_metrics
  suspended_processes       = ["AZRebalance"]

  # fleeting-plugin-aws requires both: the plugin, not the group, chooses
  # which instance goes, and removes it with
  # TerminateInstanceInAutoScalingGroup, which protection does not block.
  # Without protection the group picks its own instance on scale-in, and that
  # one may be running a job.
  protect_from_scale_in = true

  dynamic "tag" {
    for_each = merge(
      local.tags,
      local.pool_instances[each.key].additional_tags,
      # overwrites the `Name` key from `local.tags`
      local.pool_instances[each.key].name_prefix == "" ? { Name = substr(format("%s", var.environment), 0, 16) } : { Name = local.pool_instances[each.key].name_prefix },
    )

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  # An ASG takes either a launch template or a mixed instances policy, never
  # both. Without overrides it keeps the plain template; with them it launches
  # spot across every listed type, in the consumer's order.
  dynamic "launch_template" {
    for_each = length(local.runner_instance_type_overrides[each.key]) == 0 ? [0] : []
    content {
      id      = each.value.id
      version = each.value.latest_version
    }
  }

  dynamic "mixed_instances_policy" {
    for_each = length(local.runner_instance_type_overrides[each.key]) == 0 ? [] : [0]
    content {
      instances_distribution {
        on_demand_base_capacity                  = 0
        on_demand_percentage_above_base_capacity = 0
        spot_allocation_strategy                 = "price-capacity-optimized"
        spot_max_price                           = local.runner_spot_max_price[each.key]
      }

      launch_template {
        launch_template_specification {
          launch_template_id = each.value.id
          version            = each.value.latest_version
        }

        dynamic "override" {
          for_each = local.runner_instance_type_overrides[each.key]
          content {
            instance_type = override.value
          }
        }
      }
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
      # Every runner is protected from scale-in. "Ignore" skips protected
      # runners, so a refresh never waits on or terminates one that may be
      # running a job; the plugin retires runners itself. The AWS provider
      # already defaults to it, but the API's own default, "Wait", would stall
      # each refresh for an hour and then fail it, so it is not left implicit.
      scale_in_protected_instances = "Ignore"
    }
    triggers = ["tag"]
  }

  lifecycle {
    ignore_changes = [min_size, max_size, desired_capacity]
  }
}
