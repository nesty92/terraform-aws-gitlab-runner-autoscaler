locals {
  tags_merged = merge(
    {
      "Name" = format("%s", var.environment)
    },
    {
      "Environment" = format("%s", var.environment)
    },
    var.tags,
  )

  tags = { for k, v in local.tags_merged : k => v if !contains(var.suppressed_tags, k) }

  runner_docker_options = {
    arm64 = merge({
      for key, value in var.runner_docker_options_arm64 : key => value if value != null
    }, {})
    amd64 = merge({
      for key, value in var.runner_docker_options_amd64 : key => value if value != null
    }, {})
  }

  runner_autoscaler_options = {
    arm64 = merge({
      for key, value in var.runner_autoscaler_options_arm64 : key => value if value != null
    }, {})
    amd64 = merge({
      for key, value in var.runner_autoscaler_options_amd64 : key => value if value != null
    }, {})
  }

  runner_autoscaler_plugin_connector_options = {
    arm64 = merge({
      for key, value in var.runner_autoscaler_plugin_connector_options_arm64 : key => value if value != null
    }, {})
    amd64 = merge({
      for key, value in var.runner_autoscaler_plugin_connector_options_amd64 : key => value if value != null
    }, {})
  }

  runner_autoscaler_plugin_options = {
    arm64 = merge({
      for key, value in var.runner_autoscaler_plugin_options_arm64 : key => value if value != null
    }, { name = try(aws_autoscaling_group.gitlab_runner_instance["arm64"].name, null) })
    amd64 = merge({
      for key, value in var.runner_autoscaler_plugin_options_amd64 : key => value if value != null
    }, { name = try(aws_autoscaling_group.gitlab_runner_instance["amd64"].name, null) })
  }

  runner_autoscaler_policy_arm64_cleaned = [
    for policy in var.runner_autoscaler_policy_arm64 : {
      for key, value in policy : key => value if value != null
    }
  ]

  runner_autoscaler_policy_amd64_cleaned = [
    for policy in var.runner_autoscaler_policy_amd64 : {
      for key, value in policy : key => value if value != null
    }
  ]

  runner_autoscaler_policy = {
    arm64 = local.runner_autoscaler_policy_arm64_cleaned
    amd64 = local.runner_autoscaler_policy_amd64_cleaned
  }

  runner_tokens = {
    arm64 = var.runner_ssm_token_arm64
    amd64 = var.runner_ssm_token_amd64
  }

  runner_instances = {
    amd64 = var.runner_instance_amd64
    arm64 = var.runner_instance_arm64
  }

  template_runner_config = templatefile("${path.module}/templates/runner_manager.tftpl",
    {
      gitlab_check_interval     = var.runner_manager.gitlab_check_interval
      maximum_concurrent_jobs   = var.runner_manager.maximum_concurrent_jobs
      prometheus_listen_address = var.runner_manager.prometheus_listen_address
      sentry_dsn                = var.runner_manager.sentry_dsn

      runners_autoscaling = [
        for arch in var.architectures : {
          name   = format("runner-%s", arch)
          url    = var.gitlab_instance_url
          token  = local.runner_tokens[arch].name
          shell  = "sh"
          plugin = "fleeting-plugin-aws"


          docker           = local.runner_docker_options[arch]
          autoscaler       = local.runner_autoscaler_options[arch]
          connector_config = local.runner_autoscaler_plugin_connector_options[arch]
          plugin_config    = local.runner_autoscaler_plugin_options[arch]
          policy           = local.runner_autoscaler_policy[arch]
        }
      ]
    }
  )
}
