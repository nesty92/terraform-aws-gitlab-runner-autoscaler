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

  docker_options_by_arch = {
    arm64 = { for k, v in var.runner_docker_options_arm64 : k => v if v != null }
    amd64 = { for k, v in var.runner_docker_options_amd64 : k => v if v != null }
  }

  autoscaler_options_by_arch = {
    arm64 = { for k, v in var.runner_autoscaler_options_arm64 : k => v if v != null }
    amd64 = { for k, v in var.runner_autoscaler_options_amd64 : k => v if v != null }
  }

  plugin_connector_options_by_arch = {
    arm64 = { for k, v in var.runner_autoscaler_plugin_connector_options_arm64 : k => v if v != null }
    amd64 = { for k, v in var.runner_autoscaler_plugin_connector_options_amd64 : k => v if v != null }
  }

  plugin_options_by_arch = {
    arm64 = merge(
      { for k, v in var.runner_autoscaler_plugin_options_arm64 : k => v if v != null },
      { name = try(aws_autoscaling_group.gitlab_runner_instance["arm64"].name, null) }
    )
    amd64 = merge(
      { for k, v in var.runner_autoscaler_plugin_options_amd64 : k => v if v != null },
      { name = try(aws_autoscaling_group.gitlab_runner_instance["amd64"].name, null) }
    )
  }

  policy_by_arch = {
    arm64 = [for policy in var.runner_autoscaler_policy_arm64 : { for k, v in policy : k => v if v != null }]
    amd64 = [for policy in var.runner_autoscaler_policy_amd64 : { for k, v in policy : k => v if v != null }]
  }

  runner_docker_options = {
    for arch in var.architectures : arch => lookup(local.docker_options_by_arch, arch, {})
  }

  runner_autoscaler_options = {
    for arch in var.architectures : arch => lookup(local.autoscaler_options_by_arch, arch, {})
  }

  runner_autoscaler_plugin_connector_options = {
    for arch in var.architectures : arch => lookup(local.plugin_connector_options_by_arch, arch, {})
  }

  runner_autoscaler_plugin_options = {
    for arch in var.architectures : arch => lookup(local.plugin_options_by_arch, arch, {})
  }

  runner_autoscaler_policy = {
    for arch in var.architectures : arch => lookup(local.policy_by_arch, arch, [])
  }

  runner_tokens = {
    for arch in var.architectures : arch => (
      arch == "arm64" ? var.runner_ssm_token_arm64 :
      arch == "amd64" ? var.runner_ssm_token_amd64 : null
    )
  }

  runner_instances = {
    for arch in var.architectures : arch => (
      arch == "arm64" ? var.runner_instance_arm64 :
      arch == "amd64" ? var.runner_instance_amd64 : null
    )
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


          docker            = local.runner_docker_options[arch]
          autoscaler        = local.runner_autoscaler_options[arch]
          connector_config  = local.runner_autoscaler_plugin_connector_options[arch]
          plugin_config     = local.runner_autoscaler_plugin_options[arch]
          policy            = local.runner_autoscaler_policy[arch]
          aws_region        = data.aws_region.current.name
          cache_bucket_name = var.cache_bucket_name
          access_key        = var.access_key
          secret_key        = var.secret_key
        }
      ]
    }
  )
}
