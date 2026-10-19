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

  # The ports the manager reaches a Runner instance on, keyed by the protocol
  # that names them in the rules' descriptions.
  runner_manager_to_runner_ports = {
    SSH   = { from_port = 22, to_port = 22 }
    WinRM = { from_port = 5985, to_port = 5986 }
  }

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
    for key in local.pool_order : key => (
      length(coalesce(local.pool_instances[key].instance_type_overrides, [])) == 0
      ? []
      : distinct(concat(
        [for override in local.pool_instances[key].instance_type_overrides : override.instance_type],
        [local.pool_instances[key].type],
      ))
    )
  }

  # The ceiling the consumer asked for, or null for "pay up to the on-demand
  # price". Both the launch template's spot options and the mixed policy's
  # distribution read it, so the two cannot disagree about what was asked.
  runner_spot_max_price = {
    for key in local.pool_order : key => (
      # coalesce folds null and "" into "on-demand-price"; contains() refuses a
      # null value outright.
      coalesce(local.pool_instances[key].spot_price, "on-demand-price") == "on-demand-price"
      ? null
      : local.pool_instances[key].spot_price
    )
  }

  # The consumer's runner_pools, normalised. A pool is one more [[runners]]
  # entry with its own launch template, Auto Scaling group and token; the
  # per-architecture runners keep their own keys (amd64, arm64), so adding a
  # pool moves nothing in state.
  pool_keys  = sort(keys(var.runner_pools))
  pool_order = concat(var.architectures, local.pool_keys)

  pool_executor_defaults = {
    "docker-autoscaler" = { capacity_per_instance = 1, max_use_count = 10, max_instances = 2 }
    # The job runs on the VM itself, so a reused VM would carry one job's
    # state into the next.
    "instance" = { capacity_per_instance = 1, max_use_count = 1, max_instances = 2 }
  }

  custom_pool_instances = {
    for key, pool in var.runner_pools : key => {
      ami_id                      = pool.ami_id
      additional_tags             = pool.instance.additional_tags
      collect_autoscaling_metrics = pool.instance.collect_autoscaling_metrics
      ebs_optimized               = pool.instance.ebs_optimized
      max_lifetime_seconds        = pool.instance.max_lifetime_seconds
      monitoring                  = pool.instance.monitoring
      name_prefix                 = coalesce(pool.instance.name_prefix, format("gitlab-runner-%s", key))
      private_address_only        = pool.instance.private_address_only
      block_device_mappings       = pool.instance.block_device_mappings
      spot_price                  = pool.instance.spot_price
      ssm_access                  = pool.instance.ssm_access
      type                        = pool.instance.type
      instance_type_overrides     = pool.instance.instance_type_overrides
      use_eip                     = pool.instance.use_eip
      iam_instance_profile        = pool.instance.iam_instance_profile
      security_group_ids          = pool.instance.security_group_ids
      cpu_options                 = pool.instance.cpu_options
    }
  }

  pool_instances = merge(local.runner_instances, local.custom_pool_instances)

  pool_user_data = {
    for key, pool in var.runner_pools : key => base64encode(pool.instance.user_data) if pool.instance.user_data != null
  }

  pool_subnet_ids = {
    for key, pool in var.runner_pools : key => pool.instance.subnet_ids if pool.instance.subnet_ids != null
  }

  custom_pool_autoscaler_options = {
    for key, pool in var.runner_pools : key => merge(
      local.pool_executor_defaults[pool.executor],
      { for k, v in pool.autoscaler : k => v if v != null },
    )
  }

  pool_autoscaler_options = merge(local.runner_autoscaler_options, local.custom_pool_autoscaler_options)

  pool_tokens = merge(local.runner_tokens, { for key, pool in var.runner_pools : key => pool.token })

  # A pool's token is substituted for a fixed placeholder rather than for the
  # parameter's name, which sed would misread when it holds a "/" or is a
  # prefix of another name.
  pool_token_placeholders = { for key in local.pool_keys : key => format("__RUNNER_TOKEN_%s__", upper(replace(key, "-", "_"))) }

  pool_runner_entries = {
    for key, pool in var.runner_pools : key => {
      name     = format("runner-%s", key)
      url      = var.gitlab_instance_url
      token    = local.pool_token_placeholders[key]
      shell    = "sh"
      plugin   = "fleeting-plugin-aws"
      executor = pool.executor

      docker = pool.executor != "docker-autoscaler" ? null : merge(
        { for k, v in coalesce(pool.docker, {}) : k => v if v != null },
        pool.privileged ? { privileged = true } : {},
      )
      autoscaler = local.custom_pool_autoscaler_options[key]
      connector_config = merge(
        { arch = pool.architecture },
        pool.executor == "instance" && pool.privileged ? { username = "root" } : {},
        { for k, v in pool.connector : k => v if v != null },
      )
      plugin_config = merge(
        { for k, v in pool.plugin : k => v if v != null },
        { name = format("gitlab-runner-%s-asg", key) },
      )
      policy = [for policy in pool.policy : { for k, v in policy : k => v if v != null }]
    }
  }

  runner_manager_template_vars = {
    request_concurrency = var.runner_manager.request_concurrency

    # The module's own flag first, so a consumer's entry for the same key wins.
    feature_flags = merge(
      { FF_USE_FLEETING_ACQUIRE_HEARTBEATS = true },
      var.runner_manager.feature_flags,
    )
  }

  # Each pool's [[runners]] entry on its own, appended to config.toml by the
  # Manager's user data only once its token checks out.
  pool_runner_configs = {
    for key in local.pool_keys : key => templatefile("${path.module}/templates/runners.tftpl", merge(
      local.runner_manager_template_vars,
      { runners_autoscaling = [local.pool_runner_entries[key]] },
    ))
  }

  arch_runner_entries = [
    for arch in var.architectures : {
      name     = format("runner-%s", arch)
      url      = var.gitlab_instance_url
      token    = local.runner_tokens[arch].name
      shell    = "sh"
      plugin   = "fleeting-plugin-aws"
      executor = "docker-autoscaler"

      docker           = local.runner_docker_options[arch]
      autoscaler       = local.runner_autoscaler_options[arch]
      connector_config = local.runner_autoscaler_plugin_connector_options[arch]
      plugin_config    = local.runner_autoscaler_plugin_options[arch]
      policy           = local.runner_autoscaler_policy[arch]
    }
  ]

  template_runner_config = templatefile("${path.module}/templates/runner_manager.tftpl", {
    gitlab_check_interval     = var.runner_manager.gitlab_check_interval
    maximum_concurrent_jobs   = var.runner_manager.maximum_concurrent_jobs
    prometheus_listen_address = var.runner_manager.prometheus_listen_address
    sentry_dsn                = var.runner_manager.sentry_dsn

    runners = templatefile("${path.module}/templates/runners.tftpl", merge(
      local.runner_manager_template_vars,
      { runners_autoscaling = local.arch_runner_entries },
    ))
  })
}
