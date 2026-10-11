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

  # The extra instance types the group may launch besides `type`. Empty is the
  # ordinary case and keeps the group on a plain launch template; a non-empty
  # list turns it into a mixed instances policy, which is the only shape an ASG
  # has for "try another type when this one is short".
  #
  # The overrides keep the consumer's order, and `type` is appended unless the
  # list already names it: a mixed policy launches only the types its overrides
  # list, so the base type must be among them to stay launchable.
  runner_instance_type_overrides = {
    for arch in var.architectures : arch => (
      length(coalesce(local.runner_instances[arch].instance_type_overrides, [])) == 0
      ? []
      : distinct(concat(
        [for override in local.runner_instances[arch].instance_type_overrides : override.instance_type],
        [local.runner_instances[arch].type],
      ))
    )
  }

  # The ceiling the consumer asked for, or null for "pay up to the on-demand
  # price". Both the launch template's spot options and the mixed policy's
  # distribution read it, so the two cannot disagree about what was asked.
  runner_spot_max_price = {
    for arch in var.architectures : arch => (
      # coalesce folds null and "" into "on-demand-price"; contains() refuses a
      # null value outright.
      coalesce(local.runner_instances[arch].spot_price, "on-demand-price") == "on-demand-price"
      ? null
      : local.runner_instances[arch].spot_price
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
