# fleetci (runner_pools.<key>.fleetci): per-job VM classes on a runner pool.
# The pool keeps its token, tags, [runners.docker] and cache; only its
# [runners.autoscaler] changes, from fleeting-plugin-aws on its own Auto
# Scaling group to fleetci's plugin, which drives that group as the pool's
# class and one more group per extra class (<key>-<class>). Each such pool
# runs its own fleetci: /etc/fleetci/<key>.toml, and the plugin by a name of
# its own, fleeting-plugin-fleetci-<key>, so its watchdog can tell it apart.

locals {
  fleetci_pools = { for key in local.pool_keys : key => var.runner_pools[key] if var.runner_pools[key].fleetci != null }

  # The extra classes of every fleetci pool, keyed <pool>-<class>.
  fleetci_classes = merge([
    for key, pool in local.fleetci_pools : {
      for name, c in pool.fleetci.classes : format("%s-%s", key, name) => merge(c, { pool = key, name = name })
    }
  ]...)
  fleetci_keys = sort(keys(local.fleetci_classes))

  fleetci_instances = {
    for key, c in local.fleetci_classes : key => {
      ami_id                      = c.ami_id
      additional_tags             = { "fleetci-class" = c.name }
      collect_autoscaling_metrics = null
      ebs_optimized               = true
      max_lifetime_seconds        = null
      monitoring                  = false
      name_prefix                 = format("gitlab-runner-%s", key)
      private_address_only        = c.private_address_only
      block_device_mappings       = { device_name = "/dev/sda1", volume_size = tostring(c.volume_size) }
      spot_price                  = null
      spot_allocation_strategy    = c.spot_allocation_strategy
      ssm_access                  = false
      type                        = c.instance_types[0]
      instance_type_overrides     = [for t in slice(c.instance_types, 1, length(c.instance_types)) : { instance_type = t }]
      use_eip                     = false
      iam_instance_profile        = null
      security_group_ids          = []
      cpu_options                 = null
    }
  }

  fleetci_user_data          = { for key, c in local.fleetci_classes : key => base64encode(c.user_data) if c.user_data != null }
  fleetci_subnet_ids         = { for key, c in local.fleetci_classes : key => c.subnet_ids if c.subnet_ids != null }
  fleetci_autoscaler_options = { for key, c in local.fleetci_classes : key => { max_instances = c.max_instances } }

  # The connector settings fleetci takes; password and protocol it doesn't.
  fleetci_connector_keys = ["os", "arch", "username", "key_path", "use_static_credentials", "keepalive", "timeout", "use_external_addr"]

  # Each fleetci pool's classes as fleetci.toml lists them: the pool's own
  # group first, with the size, reuse and warm VMs the pool had, then its
  # extra classes.
  fleetci_pool_classes = {
    for key, pool in local.fleetci_pools : key => merge(
      {
        (pool.fleetci.class) = {
          asg_name              = format("gitlab-runner-%s-asg", key)
          max_instances         = local.custom_pool_autoscaler_options[key].max_instances
          capacity_per_instance = local.custom_pool_autoscaler_options[key].capacity_per_instance
          max_use_count         = local.custom_pool_autoscaler_options[key].max_use_count
          acquire_timeout       = pool.fleetci.acquire_timeout
          plugin                = { for k, v in pool.plugin : k => v if v != null }
          # fleetci's image is Ubuntu: ubuntu unless the pool's connector says otherwise.
          connector = merge(
            { timeout = "5m", username = "ubuntu", arch = pool.architecture },
            { for k, v in pool.connector : k => v if v != null && contains(local.fleetci_connector_keys, k) },
          )
          policy = [for p in pool.policy : { for k, v in p : k => v if v != null }]
        }
      },
      {
        for name, c in pool.fleetci.classes : name => {
          asg_name              = format("gitlab-runner-%s-%s-asg", key, name)
          max_instances         = c.max_instances
          capacity_per_instance = c.capacity_per_instance
          max_use_count         = c.max_use_count
          acquire_timeout       = c.acquire_timeout
          plugin                = {}
          connector             = { username = c.username, arch = c.architecture, timeout = "5m" }
          policy                = [for p in c.policy : { for k, v in p : k => v if v != null }]
        }
      },
    )
  }

  # Jobs at once on a pool's classes: its runner takes that many, and
  # concurrent grows by the extra classes' share.
  fleetci_pool_slots = {
    for key, classes in local.fleetci_pool_classes : key => sum([for c in values(classes) : c.max_instances * c.capacity_per_instance])
  }
  fleetci_extra_slots = sum(concat([0], [for c in values(local.fleetci_classes) : c.max_instances * c.capacity_per_instance]))

  # What changes in a fleetci pool's [[runners]] entry.
  fleetci_runner_override = {
    for key, pool in local.fleetci_pools : key => {
      plugin = format("/usr/bin/fleeting-plugin-fleetci-%s", key)
      autoscaler = {
        capacity_per_instance = local.fleetci_pool_slots[key]
        max_use_count         = 0
        max_instances         = 1
      }
      plugin_config    = { config_file = format("/etc/fleetci/%s.toml", key) }
      connector_config = { timeout = "5m" }
      policy           = []
      vm_isolation = {
        settings = {
          enabled      = true
          nesting_host = "unix:///fleetci/nesting.sock"
          image        = "class-$${FLEETCI_CLASS}"
        }
        # Ends inside fleetci, which logs in to the VM with its own key.
        connector_config = {
          username               = "fleetci"
          password               = "unused"
          use_static_credentials = true
          timeout                = "5m"
        }
      }
    }
  }

  # What the Manager's user data does for fleetci; null skips it.
  fleetci_manager = length(local.fleetci_pools) == 0 ? null : {
    version = trimprefix(var.fleetci_version, "v")
    pools = [
      for key, pool in local.fleetci_pools : {
        key = key
        toml = templatefile("${path.module}/templates/fleetci.toml.tftpl", {
          default_class         = pool.fleetci.class
          region                = data.aws_region.current.name
          classes               = local.fleetci_pool_classes[key]
          github                = pool.fleetci.github
          github_token_file     = format("/etc/fleetci/%s-github.token", key)
          github_runner_version = pool.fleetci.github_runner_version
        })
        github_token = try(pool.fleetci.github.token, null)
        watchdog     = pool.fleetci.watchdog
      }
    ]
  }

  fleetci_token_arns = compact([for pool in values(local.fleetci_pools) : try(pool.fleetci.github.token.arn, "")])
}
