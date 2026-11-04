# fleetci (var.fleetci): per-job VM classes. Each class is one more Auto
# Scaling group beside the pools, keyed fleetci-<class>, and one fleetci
# [[runners]] entry serves them all. Null leaves everything as it was.

locals {
  fleetci_classes = var.fleetci == null ? {} : var.fleetci.classes
  fleetci_keys    = [for name in sort(keys(local.fleetci_classes)) : format("fleetci-%s", name)]

  fleetci_instances = {
    for name, c in local.fleetci_classes : format("fleetci-%s", name) => {
      ami_id                      = c.ami_id
      additional_tags             = { "fleetci-class" = name }
      collect_autoscaling_metrics = null
      ebs_optimized               = true
      max_lifetime_seconds        = null
      monitoring                  = false
      name_prefix                 = format("gitlab-runner-fleetci-%s", name)
      private_address_only        = true
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

  fleetci_user_data = {
    for name, c in local.fleetci_classes : format("fleetci-%s", name) => base64encode(c.user_data) if c.user_data != null
  }

  fleetci_subnet_ids = {
    for name, c in local.fleetci_classes : format("fleetci-%s", name) => c.subnet_ids if c.subnet_ids != null
  }

  fleetci_autoscaler_options = {
    for name, c in local.fleetci_classes : format("fleetci-%s", name) => { max_instances = c.max_instances }
  }

  # Every GitLab job passes through fleetci's one gateway, so its capacity
  # and the runner's concurrent grow by every class's ceiling.
  fleetci_max_instances = sum(concat([0], [for c in values(local.fleetci_classes) : c.max_instances]))

  fleetci_toml = var.fleetci == null ? null : templatefile("${path.module}/templates/fleetci.toml.tftpl", {
    default_class = var.fleetci.default_class
    region        = data.aws_region.current.name
    classes = {
      for name, c in local.fleetci_classes : name => {
        asg_name        = format("gitlab-runner-fleetci-%s-asg", name)
        max_instances   = c.max_instances
        acquire_timeout = c.acquire_timeout
        username        = c.username
        policy          = [for p in c.policy : { for k, v in p : k => v if v != null }]
      }
    }
    github                = var.fleetci.github
    github_runner_version = var.fleetci.github_runner_version
  })

  fleetci_token_placeholder = "__FLEETCI_RUNNER_TOKEN__"

  # fleetci's [[runners]] entry, the values "fleetci runner-config" writes,
  # rendered like the pools' so it carries the cache, job_variables and
  # feature flags too. The Manager appends it once its token checks out.
  fleetci_runner_config = var.fleetci == null ? null : templatefile("${path.module}/templates/runners.tftpl", merge(
    local.runner_manager_template_vars,
    {
      runners_autoscaling = [{
        name        = "runner-fleetci"
        url         = var.gitlab_instance_url
        token       = local.fleetci_token_placeholder
        shell       = "sh"
        plugin      = "fleeting-plugin-fleetci"
        executor    = "docker-autoscaler"
        environment = local.docker_runner_environment
        docker      = { for k, v in var.fleetci.docker : k => v if v != null }
        autoscaler = {
          capacity_per_instance = local.fleetci_max_instances
          max_use_count         = 0
          max_instances         = 1
        }
        plugin_config    = { config_file = "/etc/fleetci/fleetci.toml" }
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
      }]
    },
  ))

  # What the Manager's user data does for fleetci; null skips it.
  fleetci_manager = var.fleetci == null ? null : {
    version          = trimprefix(var.fleetci.version, "v")
    toml             = local.fleetci_toml
    config           = local.fleetci_runner_config
    token            = var.fleetci.token
    placeholder      = local.fleetci_token_placeholder
    on_invalid_token = var.fleetci.on_invalid_token
    github_token     = try(var.fleetci.github.token, null)
  }

  fleetci_token_arns = var.fleetci == null ? [] : compact([var.fleetci.token.arn, try(var.fleetci.github.token.arn, "")])
}
