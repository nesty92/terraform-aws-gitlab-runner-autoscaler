# fleetci: per-job VM classes on a runner, either a main runner
# (runner_fleetci_amd64, runner_fleetci_arm64) or a pool
# (runner_pools.<key>.fleetci). The runner keeps its token, tags,
# [runners.docker] and cache; only its [runners.autoscaler] changes, from
# fleeting-plugin-aws on its own Auto Scaling group to fleetci's plugin, which
# drives that group as the runner's own class and one more group per extra
# class (<key>-<class>). Each such runner has a fleetci of its own:
# /etc/fleetci/<key>.toml, and the plugin by a name of its own,
# fleeting-plugin-fleetci-<key>, so its watchdog can tell it apart.

locals {
  fleetci_main = { amd64 = var.runner_fleetci_amd64, arm64 = var.runner_fleetci_arm64 }
  fleetci_main_plugin = {
    amd64 = var.runner_autoscaler_plugin_options_amd64
    arm64 = var.runner_autoscaler_plugin_options_arm64
  }

  # Every runner with fleetci, the main ones and the pools alike: what its
  # own class takes from the runner's settings.
  fleetci_runners = merge(
    {
      for arch in var.architectures : arch => {
        fleetci      = local.fleetci_main[arch]
        architecture = arch
        executor     = "docker-autoscaler"
        autoscaler   = local.runner_autoscaler_options[arch]
        plugin       = { for k, v in local.fleetci_main_plugin[arch] : k => v if v != null }
        connector    = local.runner_autoscaler_plugin_connector_options[arch]
        policy       = local.runner_autoscaler_policy[arch]
      } if local.fleetci_main[arch] != null
    },
    {
      for key in local.pool_keys : key => {
        fleetci      = var.runner_pools[key].fleetci
        architecture = var.runner_pools[key].architecture
        executor     = var.runner_pools[key].executor
        autoscaler   = local.custom_pool_autoscaler_options[key]
        plugin       = { for k, v in var.runner_pools[key].plugin : k => v if v != null }
        connector    = { for k, v in var.runner_pools[key].connector : k => v if v != null }
        policy       = [for p in var.runner_pools[key].policy : { for k, v in p : k => v if v != null }]
      } if var.runner_pools[key].fleetci != null
    },
  )

  # The extra classes of every fleetci runner, keyed <runner>-<class>.
  fleetci_classes = merge([
    for key, r in local.fleetci_runners : {
      for name, c in r.fleetci.classes : format("%s-%s", key, name) => merge(c, { runner = key, name = name })
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
      # An empty instance_types is refused by the Manager's precondition.
      type                    = try(c.instance_types[0], null)
      instance_type_overrides = [for i, t in c.instance_types : { instance_type = t } if i > 0]
      use_eip                 = false
      iam_instance_profile    = null
      security_group_ids      = []
      cpu_options             = null
    }
  }

  fleetci_user_data          = { for key, c in local.fleetci_classes : key => base64encode(c.user_data) if c.user_data != null }
  fleetci_subnet_ids         = { for key, c in local.fleetci_classes : key => c.subnet_ids if c.subnet_ids != null }
  fleetci_autoscaler_options = { for key, c in local.fleetci_classes : key => { max_instances = c.max_instances } }

  # The connector settings fleetci takes; password and protocol it doesn't.
  fleetci_connector_keys = ["os", "arch", "username", "key_path", "use_static_credentials", "keepalive", "timeout", "use_external_addr"]

  # Each fleetci runner's classes as fleetci.toml lists them: the runner's
  # own group first, with the size, reuse and warm VMs it had, then its extra
  # classes.
  fleetci_runner_classes = {
    for key, r in local.fleetci_runners : key => merge(
      {
        (r.fleetci.class) = {
          asg_name              = format("gitlab-runner-%s-asg", key)
          max_instances         = r.autoscaler.max_instances
          capacity_per_instance = r.autoscaler.capacity_per_instance
          max_use_count         = r.autoscaler.max_use_count
          acquire_timeout       = r.fleetci.acquire_timeout
          plugin                = r.plugin
          # fleetci's image is Ubuntu: ubuntu unless the runner's connector says otherwise.
          connector = merge(
            { timeout = "5m", username = "ubuntu", arch = r.architecture },
            { for k, v in r.connector : k => v if contains(local.fleetci_connector_keys, k) },
          )
          policy = r.policy
        }
      },
      {
        for name, c in r.fleetci.classes : name => {
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

  # Jobs at once on a runner's classes: it takes that many, and concurrent
  # grows by the extra classes' share.
  fleetci_runner_slots = {
    for key, classes in local.fleetci_runner_classes : key => sum([for c in values(classes) : c.max_instances * c.capacity_per_instance])
  }
  fleetci_extra_slots = sum(concat([0], [for c in values(local.fleetci_classes) : c.max_instances * c.capacity_per_instance]))

  # What changes in a fleetci runner's [[runners]] entry.
  fleetci_runner_override = {
    for key in keys(local.fleetci_runners) : key => {
      plugin = format("/usr/bin/fleeting-plugin-fleetci-%s", key)
      autoscaler = {
        capacity_per_instance = local.fleetci_runner_slots[key]
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
  fleetci_manager = length(local.fleetci_runners) == 0 ? null : {
    version = trimprefix(var.fleetci_version, "v")
    runners = [
      for key, r in local.fleetci_runners : {
        key = key
        toml = templatefile("${path.module}/templates/fleetci.toml.tftpl", {
          default_class         = r.fleetci.class
          region                = data.aws_region.current.name
          classes               = local.fleetci_runner_classes[key]
          github                = r.fleetci.github
          github_token_file     = format("/etc/fleetci/%s-github.token", key)
          github_runner_version = r.fleetci.github_runner_version
        })
        github_token = try(r.fleetci.github.token, null)
        watchdog     = r.fleetci.watchdog
      }
    ]
  }

  # What the Manager's preconditions refuse, as the runners at fault.
  fleetci_spot_strategies = ["price-capacity-optimized", "capacity-optimized", "capacity-optimized-prioritized", "lowest-price"]
  fleetci_refused = {
    executor = [for key, r in local.fleetci_runners : format("runner-%s", key) if r.executor != "docker-autoscaler"]
    names = [
      for key, r in local.fleetci_runners : format("runner-%s", key)
      if !alltrue([for name in concat([r.fleetci.class], keys(r.fleetci.classes)) : can(regex("^[a-z0-9][a-z0-9-]{0,29}$", name))]) || contains(keys(r.fleetci.classes), r.fleetci.class)
    ]
    classes = [
      for key, r in local.fleetci_runners : format("runner-%s", key)
      if !alltrue([for c in values(r.fleetci.classes) : contains(["amd64", "arm64"], c.architecture) && length(c.instance_types) > 0 && c.max_instances >= 1 && c.capacity_per_instance >= 1 && c.max_use_count >= 1])
    ]
    spot = [
      for key, r in local.fleetci_runners : format("runner-%s", key)
      if !alltrue([for c in values(r.fleetci.classes) : contains(local.fleetci_spot_strategies, c.spot_allocation_strategy)])
    ]
    # GitHub steps run on the VM itself, so every class must run one job per VM.
    reuse_with_github = [
      for key, classes in local.fleetci_runner_classes : format("runner-%s", key)
      if local.fleetci_runners[key].fleetci.github != null && !alltrue([for c in values(classes) : c.capacity_per_instance == 1 && c.max_use_count == 1])
    ]
  }
  fleetci_repos = flatten([for r in values(local.fleetci_runners) : try(r.fleetci.github.repos, [])])

  fleetci_token_arns = compact([for r in values(local.fleetci_runners) : try(r.fleetci.github.token.arn, "")])
}
