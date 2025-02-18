resource "aws_security_group" "runner" {
  name_prefix = "gitlab-runner"
  description = "Security group for GitLab Runner instances"
  vpc_id      = var.aws_vpc_id

  ingress {
    description     = "Allow SSH access from the Runner Manager"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.runner_manager.id]
  }

  ingress {
    description     = "Allow WinRM access from the Runner Manager"
    from_port       = 5985
    to_port         = 5986
    protocol        = "tcp"
    security_groups = [aws_security_group.runner_manager.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "runner_manager" {
  name_prefix = "gitlab-runner-manager"
  description = "Security group for the GitLab Runner Manager instance"
  vpc_id      = var.aws_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
          for arch in var.architectures : local.runner_tokens[arch].arn if local.runner_tokens[arch] != null
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
        Resource = [for arch in var.architectures : aws_autoscaling_group.gitlab_runner_instance[arch].arn]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:DescribeInstances"
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
            "ec2:ResourceTag/aws:autoscaling:groupName" : [for arch in var.architectures : aws_autoscaling_group.gitlab_runner_instance[arch].name]
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


resource "aws_instance" "runner_manager" {
  ami                  = data.aws_ami.amazon_linux_2.id
  instance_type        = "t2.nano"
  iam_instance_profile = aws_iam_instance_profile.runner_manager.name

  associate_public_ip_address = false

  vpc_security_group_ids = [aws_security_group.runner_manager.id]

  subnet_id = var.aws_subnet_ids[0]

  user_data = base64encode(templatefile("${path.module}/templates/runner_manager_user_data.tftpl", {
    aws_region         = data.aws_region.current.name,
    runners_config     = local.template_runner_config
    runners_gitlab_url = var.gitlab_instance_url
    runner_tokens      = { for arch in var.architectures : arch => local.runner_tokens[arch] if local.runner_tokens[arch] != null }

    fleeting_plugin_aws_version = var.fleeting_plugin_aws_version
    gitlab_runner_version       = var.gitlab_runner_version
  }))
  user_data_replace_on_change = true

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
  for_each = toset(var.architectures)

  name = local.runner_instances[each.key].name_prefix

  image_id               = local.runner_instances[each.key].ami_id
  instance_type          = local.runner_instances[each.key].type
  update_default_version = true
  ebs_optimized          = local.runner_instances[each.key].ebs_optimized

  monitoring {
    enabled = local.runner_instances[each.key].monitoring
  }

  instance_market_options {
    market_type = "spot"
    dynamic "spot_options" {
      for_each = local.runner_instances[each.key].spot_price == null || local.runner_instances[each.key].spot_price == "" || local.runner_instances[each.key].spot_price == "on-demand-price" ? [] : [0]
      content {
        max_price = local.runner_instances[each.key].spot_price
      }
    }
  }

  dynamic "iam_instance_profile" {
    for_each = local.runner_instances[each.key].iam_instance_profile == null ? [] : [0]
    content {
      name = local.runner_instances[each.key].iam_instance_profile
    }
  }

  dynamic "block_device_mappings" {
    for_each = [local.runner_instances[each.key].block_device_mappings]
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
    security_groups             = concat([aws_security_group.runner.id], local.runner_instances[each.key].security_group_ids)
    associate_public_ip_address = local.runner_instances[each.key].private_address_only == false
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.tags,
      local.runner_instances[each.key].additional_tags,
      # overwrites the `Name` key from `local.tags`
      local.runner_instances[each.key].name_prefix == "" ? { Name = substr(format("%s", var.environment), 0, 16) } : { Name = local.runner_instances[each.key].name_prefix },
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }

  dynamic "tag_specifications" {
    for_each = local.runner_instances[each.key].spot_price == null || local.runner_instances[each.key].spot_price == "" ? [] : ["spot"]
    content {
      resource_type = "spot-instances-request"
      tags          = local.tags
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
  vpc_zone_identifier       = var.aws_subnet_ids
  min_size                  = 0
  max_size                  = local.runner_autoscaler_options[each.key].max_instances
  desired_capacity          = 0
  health_check_grace_period = 0
  max_instance_lifetime     = local.runner_instances[each.key].max_lifetime_seconds
  enabled_metrics           = local.runner_instances[each.key].collect_autoscaling_metrics

  dynamic "tag" {
    for_each = merge(
      local.tags,
      local.runner_instances[each.key].additional_tags,
      # overwrites the `Name` key from `local.tags`
      local.runner_instances[each.key].name_prefix == "" ? { Name = substr(format("%s", var.environment), 0, 16) } : { Name = local.runner_instances[each.key].name_prefix },
    )

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  launch_template {
    id      = each.value.id
    version = each.value.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
    triggers = ["tag"]
  }

  lifecycle {
    ignore_changes = [min_size, max_size, desired_capacity]
  }
}
