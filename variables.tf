variable "environment" {
  description = "A name that identifies the environment, used as a prefix for tagging resources"
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "suppressed_tags" {
  description = "List of tag keys which are automatically removed and never added as default tag by the module."
  type        = list(string)
  default     = []
}

variable "gitlab_instance_url" {
  description = "The URL of the GitLab instance"
  type        = string
  default     = "https://gitlab.com"
}

variable "architectures" {
  description = "The architectures that the Runner will support (e.g., arm64, amd64). Each specified architecture requires its corresponding runner_instance configuration."
  type        = list(string)
  validation {
    condition     = length(var.architectures) > 0 && alltrue([for arch in var.architectures : contains(["arm64", "amd64"], arch)])
    error_message = "The architectures list must only include 'arm64' and 'amd64'."
  }
}

variable "aws_vpc_id" {
  type = string
}

variable "aws_subnet_ids" {
  type = list(string)
}

variable "fleeting_plugin_aws_version" {
  description = "The version of the AWS Fleeting plugin to install."
  type        = string
}

variable "gitlab_runner_version" {
  description = "The version of the GitLab Runner to install."
  type        = string
}

variable "runner_ssm_token_arm64" {
  description = "The SSM parameter that stores the authentication token for the Runner (arm64). Required when arm64 architecture is specified."
  type = object({
    name   = string
    arn    = string
    region = string
  })
  default = null
  validation {
    condition     = var.runner_ssm_token_arm64 != null || !contains(coalesce(var.architectures, []), "arm64")
    error_message = "runner_ssm_token_arm64 is required when arm64 architecture is specified."
  }
}

variable "runner_ssm_token_amd64" {
  description = "The SSM parameter that stores the authentication token for the Runner (amd64). Required when amd64 architecture is specified."
  type = object({
    name   = string
    arn    = string
    region = string
  })
  default = null
  validation {
    condition     = var.runner_ssm_token_amd64 != null || !contains(coalesce(var.architectures, []), "amd64")
    error_message = "runner_ssm_token_amd64 is required when amd64 architecture is specified."
  }
}

variable "runner_manager" {
  description = <<-EOT
    For details check https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-global-section

    gitlab_check_interval = Number of seconds between checking for available jobs (check_interval)
    maximum_concurrent_jobs = The maximum number of jobs which can be processed by all Runners at the same time (concurrent).
    prometheus_listen_address = Defines an address (<host>:<port>) the Prometheus metrics HTTP server should listen on (listen_address).
    sentry_dsn = Sentry DSN of the project for the Runner Manager to use (uses legacy DSN format) (sentry_dsn)
    request_concurrency = Limit of concurrent requests for new jobs from GitLab, set on every [[runners]] entry (request_concurrency). Omitted from config.toml when null.
    feature_flags = Extra Runner feature flags set on every [[runners]] entry, merged over the module's FF_USE_FLEETING_ACQUIRE_HEARTBEATS = true. See https://docs.gitlab.com/runner/configuration/feature-flags/
    enable_ssm_agent = Enable and start amazon-ssm-agent on the Runner Manager from its user data.
  EOT
  type = object({
    gitlab_check_interval     = optional(number, 3)
    maximum_concurrent_jobs   = optional(number, 10)
    prometheus_listen_address = optional(string, "")
    sentry_dsn                = optional(string, "")
    request_concurrency       = optional(number)
    feature_flags             = optional(map(bool), {})
    enable_ssm_agent          = optional(bool, false)
  })
  default = {}
}

variable "ecr_job_images" {
  description = <<-EOT
    Lets jobs on the docker-autoscaler runners use images from this account's ECR with no login in CI. The Manager installs
    amazon-ecr-credential-helper and signs each pull with its own role; the instances need no ECR access, since the layers
    come from S3 URLs the registry hands out.

    repository_arns = The ECR repositories (wildcards allowed) a job may pull its image and services from.
    pull_through_cache_arns = Pull-through cache repositories. A job may pull from them too, and its first pull of an
                              image may create the repository and copy the image from the upstream.
  EOT
  type = object({
    repository_arns         = list(string)
    pull_through_cache_arns = optional(list(string), [])
  })
  default = null
}

variable "runner_manager_instance_type" {
  description = "EC2 instance type for the Runner Manager. Must support EBS optimization."
  type        = string
  default     = "t3.nano"
}

# Docker options for the Runner Worker
variable "runner_docker_options_amd64" {
  description = <<EOT
    Options added to the [runners.docker] section of config.toml to configure the Docker container of the Runner Worker. For
    details check https://docs.gitlab.com/runner/configuration/advanced-configuration.html

    Default values if the option is not given:
      disable_cache = "false"
      image         = "busybox:latest"
      privileged    = "false"
      pull_policy   = "always"
      shm_size      = 0
      tls_verify    = "false"
      volumes       = "/cache"
  EOT

  type = object({
    allowed_images                   = optional(list(string))
    allowed_privileged_images        = optional(list(string))
    allowed_pull_policies            = optional(list(string))
    allowed_services                 = optional(list(string))
    allowed_privileged_services      = optional(list(string))
    cache_dir                        = optional(string)
    cap_add                          = optional(list(string))
    cap_drop                         = optional(list(string))
    cpuset_cpus                      = optional(string)
    cpu_shares                       = optional(number)
    cpus                             = optional(string)
    devices                          = optional(list(string))
    device_cgroup_rules              = optional(list(string))
    disable_cache                    = optional(bool, false)
    disable_entrypoint_overwrite     = optional(bool)
    dns                              = optional(list(string))
    dns_search                       = optional(list(string))
    extra_hosts                      = optional(list(string))
    gpus                             = optional(string)
    group_add                        = optional(list(string))
    helper_image                     = optional(string)
    helper_image_flavor              = optional(string)
    helper_image_autoset_arch_and_os = optional(bool)
    host                             = optional(string)
    hostname                         = optional(string)
    image                            = optional(string, "busybox:latest")
    links                            = optional(list(string))
    memory                           = optional(string)
    memory_swap                      = optional(string)
    memory_reservation               = optional(string)
    network_mode                     = optional(string)
    mac_address                      = optional(string)
    oom_kill_disable                 = optional(bool)
    oom_score_adjust                 = optional(number)
    privileged                       = optional(bool, false)
    services_privileged              = optional(string)
    pull_policy                      = optional(list(string), ["always"])
    runtime                          = optional(string)
    isolation                        = optional(string)
    security_opt                     = optional(list(string))
    shm_size                         = optional(number, 0)
    sysctls                          = optional(map(string))
    tls_cert_path                    = optional(string)
    tls_verify                       = optional(bool, false)
    user                             = optional(string)
    userns_mode                      = optional(string)
    ulimit                           = optional(list(string))
    volumes                          = optional(list(string), [])
    volumes_from                     = optional(list(string))
    volume_driver                    = optional(string)
    wait_for_services_timeout        = optional(number)
    container_labels                 = optional(map(string))
    services_limit                   = optional(number)
    service_cpuset_cpus              = optional(string)
    service_cpu_shares               = optional(number)
    service_cpus                     = optional(string)
    service_memory                   = optional(string)
    service_memory_swap              = optional(string)
    service_memory_reservation       = optional(string)
  })

  default = {
    disable_cache = false
    image         = "busybox:latest"
    privileged    = false
    pull_policies = ["always"]
    shm_size      = 0
    tls_verify    = false
    volumes       = ["/cache"]
  }
}

variable "runner_docker_options_arm64" {
  description = <<EOT
    Options added to the [runners.docker] section of config.toml to configure the Docker container of the Runner Worker. For
    details check https://docs.gitlab.com/runner/configuration/advanced-configuration.html

    Default values if the option is not given:
      disable_cache = false
      image         = "busybox:latest"
      privileged    = false
      pull_policy   = "always"
      shm_size      = 0
      tls_verify    = false
      volumes       = "/cache"
  EOT

  type = object({
    allowed_images                   = optional(list(string))
    allowed_privileged_images        = optional(list(string))
    allowed_pull_policies            = optional(list(string))
    allowed_services                 = optional(list(string))
    allowed_privileged_services      = optional(list(string))
    cache_dir                        = optional(string)
    cap_add                          = optional(list(string))
    cap_drop                         = optional(list(string))
    cpuset_cpus                      = optional(string)
    cpu_shares                       = optional(number)
    cpus                             = optional(string)
    devices                          = optional(list(string))
    device_cgroup_rules              = optional(list(string))
    disable_cache                    = optional(bool, false)
    disable_entrypoint_overwrite     = optional(bool)
    dns                              = optional(list(string))
    dns_search                       = optional(list(string))
    extra_hosts                      = optional(list(string))
    gpus                             = optional(string)
    group_add                        = optional(list(string))
    helper_image                     = optional(string)
    helper_image_flavor              = optional(string)
    helper_image_autoset_arch_and_os = optional(bool)
    host                             = optional(string)
    hostname                         = optional(string)
    image                            = optional(string, "busybox:latest")
    links                            = optional(list(string))
    memory                           = optional(string)
    memory_swap                      = optional(string)
    memory_reservation               = optional(string)
    network_mode                     = optional(string)
    mac_address                      = optional(string)
    oom_kill_disable                 = optional(bool)
    oom_score_adjust                 = optional(number)
    privileged                       = optional(bool, false)
    services_privileged              = optional(string)
    pull_policy                      = optional(list(string), ["always"])
    runtime                          = optional(string)
    isolation                        = optional(string)
    security_opt                     = optional(list(string))
    shm_size                         = optional(number, 0)
    sysctls                          = optional(map(string))
    tls_cert_path                    = optional(string)
    tls_verify                       = optional(bool, false)
    user                             = optional(string)
    userns_mode                      = optional(string)
    ulimit                           = optional(list(string))
    volumes                          = optional(list(string), [])
    volumes_from                     = optional(list(string))
    volume_driver                    = optional(string)
    wait_for_services_timeout        = optional(number)
    container_labels                 = optional(map(string))
    services_limit                   = optional(number)
    service_cpuset_cpus              = optional(string)
    service_cpu_shares               = optional(number)
    service_cpus                     = optional(string)
    service_memory                   = optional(string)
    service_memory_swap              = optional(string)
    service_memory_reservation       = optional(string)
  })

  default = {
    disable_cache = false
    image         = "busybox:latest"
    privileged    = false
    pull_policies = ["always"]
    shm_size      = 0
    tls_verify    = false
    volumes       = ["/cache"]
  }
}
# Docker options for the Runner Worker

# Autoscaler options for the Runner Worker
variable "runner_autoscaler_options_amd64" {
  description = <<EOT
    Options added to the [runners.autoscaler] section of config.toml to configure the Runner Autoscaler. For
    details check https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnersautoscaler-section

    capacity_per_instance = The number of jobs that can be executed concurrently by a single instance.
    max_use_count = The maximum number of times an instance can be used before it is scheduled for removal.
    max_instances = The maximum number of instances that are allowed, this is regardless of the instance state (pending, running, deleting). Default: 0 (unlimited).

    The fleeting-plugin-aws is the only supported plugin.

    Default values if the option is not given:
      capacity_per_instance = 1
      max_use_count = 10
      max_instances = 2
  EOT

  type = object({
    capacity_per_instance = optional(number)
    max_use_count         = optional(number)
    max_instances         = optional(number)
  })

  default = {
    capacity_per_instance = 1
    max_use_count         = 10
    max_instances         = 2
  }
}

variable "runner_autoscaler_options_arm64" {
  description = <<EOT
    Options added to the [runners.autoscaler] section of config.toml to configure the Runner Autoscaler. For
    details check https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnersautoscaler-section

    capacity_per_instance = The number of jobs that can be executed concurrently by a single instance.
    max_use_count = The maximum number of times an instance can be used before it is scheduled for removal.
    max_instances = The maximum number of instances that are allowed, this is regardless of the instance state (pending, running, deleting). Default: 0 (unlimited).

    The fleeting-plugin-aws is the only supported plugin.

    Default values if the option is not given:
      capacity_per_instance = 1
      max_use_count = 10
      max_instances = 2
  EOT

  type = object({
    capacity_per_instance = optional(number)
    max_use_count         = optional(number)
    max_instances         = optional(number)
  })

  default = {
    capacity_per_instance = 1
    max_use_count         = 10
    max_instances         = 2
  }
}
# Autoscaler options for the Runner Worker

# Autoscaler Plugin options for the Runner Worker
variable "runner_autoscaler_plugin_options_amd64" {
  description = <<EOT
    Options added to the [runners.autoscaler.plugin_config] section of config.toml to configure the Runner Plugin. For
    details check https://gitlab.com/gitlab-org/fleeting/plugins/aws

    auto_scaling_group_name Will be set to the value of the corresponding Arch
  EOT

  type = object({
    profile_name     = optional(string)
    config_file      = optional(string)
    credentials_file = optional(string)
  })

  default = {}
}

variable "runner_autoscaler_plugin_options_arm64" {
  description = <<EOT
    Options added to the [runners.autoscaler.plugin_config] section of config.toml to configure the Runner Plugin. For
    details check https://gitlab.com/gitlab-org/fleeting/plugins/aws

    auto_scaling_group_name Will be set to the value of the corresponding Arch
  EOT

  type = object({
    profile_name     = optional(string)
    config_file      = optional(string)
    credentials_file = optional(string)
  })

  default = {}
}

variable "runner_autoscaler_plugin_connector_options_amd64" {
  description = <<EOT
    Options added to the [runners.autoscaler.connector_config] section of config.toml to configure the Runner Plugin Connector. For
    details check https://gitlab.com/gitlab-org/fleeting/plugins/aws
  EOT

  type = object({
    os                     = optional(string, "linux")
    arch                   = optional(string)
    protocol               = optional(string)
    username               = optional(string)
    password               = optional(string)
    key_path               = optional(string)
    use_static_credentials = optional(bool, false)
    keepalive              = optional(string)
    timeout                = optional(string)
    use_external_addr      = optional(bool, false)
  })

  default = {
    arch = "amd64"
  }
}

variable "runner_autoscaler_plugin_connector_options_arm64" {
  description = <<EOT
    Options added to the [runners.autoscaler.connector_config] section of config.toml to configure the Runner Plugin Connector. For
    details check https://gitlab.com/gitlab-org/fleeting/plugins/aws
  EOT

  type = object({
    os                     = optional(string, "linux")
    arch                   = optional(string)
    protocol               = optional(string)
    username               = optional(string)
    password               = optional(string)
    key_path               = optional(string)
    use_static_credentials = optional(bool, false)
    keepalive              = optional(string)
    timeout                = optional(string)
    use_external_addr      = optional(bool, false)
  })

  default = {
    arch = "arm64"
  }
}
# Autoscaler Plugin options for the Runner Worker

# Autoscaler policy for the Runner Worker
variable "runner_autoscaler_policy_amd64" {
  description = <<EOT
    Options added to the [runners.autoscaler.policy] section of config.toml to configure the Runner Autoscaler Policy. For
    details check https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnersautoscalerpolicy-section

    Default values if the option is not given:
      idle_count = 0
      idle_time = "30m"
  EOT

  type = list(object({
    periods            = optional(list(string))
    timezone           = optional(string)
    idle_count         = optional(number)
    idle_time          = optional(string)
    scale_factor       = optional(number)
    scale_factor_limit = optional(number)
  }))

  default = [{
    idle_count = 0
    idle_time  = "30m"
  }]
}

variable "runner_autoscaler_policy_arm64" {
  description = <<EOT
    Options added to the [runners.autoscaler.policy] section of config.toml to configure the Runner Autoscaler Policy. For
    details check https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnersautoscalerpolicy-section

    Default values if the option is not given:
      idle_count = 0
      idle_time = "30m"
  EOT

  type = list(object({
    periods            = optional(list(string))
    timezone           = optional(string)
    idle_count         = optional(number)
    idle_time          = optional(string)
    scale_factor       = optional(number)
    scale_factor_limit = optional(number)
  }))

  default = [{
    idle_count = 0
    idle_time  = "30m"
  }]
}
# Autoscaler policy for the Runner Worker


variable "runner_instance_amd64" {
  description = "Configuration for the AMD64 GitLab Runner instance. Required when amd64 architecture is specified."
  type = object({
    ami_id                      = string
    additional_tags             = optional(map(string))
    collect_autoscaling_metrics = optional(list(string), null)
    ebs_optimized               = optional(bool, true)
    max_lifetime_seconds        = optional(number, null)
    monitoring                  = optional(bool, false)
    name_prefix                 = optional(string)
    private_address_only        = optional(bool, true)
    block_device_mappings       = optional(map(string), {})
    spot_price                  = optional(string, null)
    spot_allocation_strategy    = optional(string, "price-capacity-optimized")
    ssm_access                  = optional(bool, false)
    type                        = optional(string, "t3.micro")
    instance_type_overrides = optional(list(object({
      instance_type = string
    })), [])
    use_eip              = optional(bool, false)
    iam_instance_profile = optional(string)
    security_group_ids   = optional(list(string), [])
    cpu_options = optional(object({
      core_count            = optional(number)
      threads_per_core      = optional(number)
      amd_sev_snp           = optional(string)
      nested_virtualization = optional(string)
    }), null)
  })
  default = null

  validation {
    condition     = var.runner_instance_amd64 == null ? true : contains(["price-capacity-optimized", "capacity-optimized", "capacity-optimized-prioritized", "lowest-price"], var.runner_instance_amd64.spot_allocation_strategy)
    error_message = "spot_allocation_strategy must be price-capacity-optimized, capacity-optimized, capacity-optimized-prioritized or lowest-price."
  }
}

variable "runner_instance_arm64" {
  description = "Configuration for the ARM64 GitLab Runner instance. Required when arm64 architecture is specified."
  type = object({
    ami_id                      = string
    additional_tags             = optional(map(string))
    collect_autoscaling_metrics = optional(list(string), null)
    ebs_optimized               = optional(bool, true)
    max_lifetime_seconds        = optional(number, null)
    monitoring                  = optional(bool, false)
    name_prefix                 = optional(string)
    private_address_only        = optional(bool, true)
    block_device_mappings       = optional(map(string), {})
    spot_price                  = optional(string, null)
    spot_allocation_strategy    = optional(string, "price-capacity-optimized")
    ssm_access                  = optional(bool, false)
    type                        = optional(string, "t4g.micro")
    instance_type_overrides = optional(list(object({
      instance_type = string
    })), [])
    use_eip              = optional(bool, false)
    iam_instance_profile = optional(string)
    security_group_ids   = optional(list(string), [])
    cpu_options = optional(object({
      core_count            = optional(number)
      threads_per_core      = optional(number)
      amd_sev_snp           = optional(string)
      nested_virtualization = optional(string)
    }), null)
  })
  default = null

  validation {
    condition     = var.runner_instance_arm64 == null ? true : contains(["price-capacity-optimized", "capacity-optimized", "capacity-optimized-prioritized", "lowest-price"], var.runner_instance_arm64.spot_allocation_strategy)
    error_message = "spot_allocation_strategy must be price-capacity-optimized, capacity-optimized, capacity-optimized-prioritized or lowest-price."
  }

  validation {
    condition     = var.runner_instance_arm64 != null || !contains(coalesce(var.architectures, []), "arm64")
    error_message = "runner_instance_arm64 is required when arm64 architecture is specified."
  }
}

variable "runner_pools" {
  description = <<-EOT
    Extra runner pools served by the same Runner Manager, keyed by a name that ends up in the pool's launch template,
    Auto Scaling group (gitlab-runner-<key>-asg) and runner (runner-<key>). Each pool is one more [[runners]] entry in
    config.toml with its own Auto Scaling group, token, executor and options, for a class the per-architecture runners
    do not cover (for example a privileged, single-use pool).

    architecture = amd64 or arm64; sets the connector's arch.
    executor = docker-autoscaler (default) or instance (the job runs directly on the VM).
    ami_id = The AMI the pool's instances boot from.
    token = The SSM parameter holding the pool's runner authentication token. Tags and run_untagged belong to the
      runner's registration in GitLab, not to this module.
    on_invalid_token = skip (default): a missing or invalid token leaves this pool out of config.toml and the Manager
      starts the other runners; fail: the Manager's boot exits, as it does for the per-architecture runners.
    privileged = With docker-autoscaler, sets [runners.docker] privileged = true; with instance, connects as root unless
      connector.username says otherwise.
    instance = Launch settings, as runner_instance_amd64 without ami_id, plus user_data (plain text, put on the pool's
      launch template) and subnet_ids (defaults to aws_subnet_ids).
    autoscaler = As runner_autoscaler_options_amd64. Defaults: capacity_per_instance = 1, max_instances = 2,
      max_use_count = 1 for instance (each VM is single-use) and 10 for docker-autoscaler.
    policy = As runner_autoscaler_policy_amd64.
    docker = [runners.docker] options, as runner_docker_options_amd64; only with docker-autoscaler.
    connector = As runner_autoscaler_plugin_connector_options_amd64.
    plugin = As runner_autoscaler_plugin_options_amd64; the Auto Scaling group's name is always set by the module.

    Adding, changing or removing a pool changes the Manager's user data, which replaces the Manager once. The global
    concurrent setting (runner_manager.maximum_concurrent_jobs) is shared by every runner.
  EOT

  type = map(object({
    architecture = string
    executor     = optional(string, "docker-autoscaler")
    ami_id       = string
    token = object({
      name   = string
      arn    = string
      region = string
    })
    on_invalid_token = optional(string, "skip")
    privileged       = optional(bool, false)

    instance = optional(object({
      additional_tags             = optional(map(string))
      collect_autoscaling_metrics = optional(list(string), null)
      ebs_optimized               = optional(bool, true)
      max_lifetime_seconds        = optional(number, null)
      monitoring                  = optional(bool, false)
      name_prefix                 = optional(string)
      private_address_only        = optional(bool, true)
      block_device_mappings       = optional(map(string), {})
      spot_price                  = optional(string, null)
      spot_allocation_strategy    = optional(string, "price-capacity-optimized")
      ssm_access                  = optional(bool, false)
      type                        = optional(string, "t3.micro")
      instance_type_overrides = optional(list(object({
        instance_type = string
      })), [])
      use_eip              = optional(bool, false)
      iam_instance_profile = optional(string)
      security_group_ids   = optional(list(string), [])
      cpu_options = optional(object({
        core_count            = optional(number)
        threads_per_core      = optional(number)
        amd_sev_snp           = optional(string)
        nested_virtualization = optional(string)
      }), null)
      user_data  = optional(string)
      subnet_ids = optional(list(string))
    }), {})

    autoscaler = optional(object({
      capacity_per_instance = optional(number)
      max_use_count         = optional(number)
      max_instances         = optional(number)
    }), {})

    policy = optional(list(object({
      periods            = optional(list(string))
      timezone           = optional(string)
      idle_count         = optional(number)
      idle_time          = optional(string)
      scale_factor       = optional(number)
      scale_factor_limit = optional(number)
    })), [{ idle_count = 0, idle_time = "30m" }])

    docker = optional(any)

    connector = optional(object({
      os                     = optional(string, "linux")
      arch                   = optional(string)
      protocol               = optional(string)
      username               = optional(string)
      password               = optional(string)
      key_path               = optional(string)
      use_static_credentials = optional(bool, false)
      keepalive              = optional(string)
      timeout                = optional(string)
      use_external_addr      = optional(bool, false)
    }), {})

    plugin = optional(object({
      profile_name     = optional(string)
      config_file      = optional(string)
      credentials_file = optional(string)
    }), {})
  }))

  default = {}

  validation {
    condition     = alltrue([for k in keys(var.runner_pools) : can(regex("^[a-z0-9-]{1,40}$", k)) && !contains(["amd64", "arm64"], k)])
    error_message = "runner_pools keys must match ^[a-z0-9-]{1,40}$ and must not be amd64 or arm64, which name the per-architecture runners."
  }

  validation {
    condition     = alltrue([for p in values(var.runner_pools) : contains(["amd64", "arm64"], p.architecture)])
    error_message = "A runner pool's architecture must be amd64 or arm64."
  }

  validation {
    condition     = alltrue([for p in values(var.runner_pools) : contains(["docker-autoscaler", "instance"], p.executor)])
    error_message = "A runner pool's executor must be docker-autoscaler or instance."
  }

  validation {
    condition     = alltrue([for p in values(var.runner_pools) : contains(["price-capacity-optimized", "capacity-optimized", "capacity-optimized-prioritized", "lowest-price"], p.instance.spot_allocation_strategy)])
    error_message = "A runner pool's instance.spot_allocation_strategy must be price-capacity-optimized, capacity-optimized, capacity-optimized-prioritized or lowest-price."
  }

  validation {
    condition     = alltrue([for p in values(var.runner_pools) : contains(["skip", "fail"], p.on_invalid_token)])
    error_message = "A runner pool's on_invalid_token must be skip or fail."
  }

  validation {
    condition     = alltrue([for p in values(var.runner_pools) : p.docker == null || p.executor == "docker-autoscaler"])
    error_message = "A runner pool's docker options apply only to the docker-autoscaler executor."
  }

  validation {
    condition     = alltrue([for p in values(var.runner_pools) : startswith(p.token.arn, "arn:aws:ssm:")])
    error_message = "A runner pool's token.arn must be an SSM parameter ARN (arn:aws:ssm:...)."
  }

  validation {
    condition = length(distinct(concat(
      [for p in values(var.runner_pools) : p.token.name],
      [for t in [var.runner_ssm_token_amd64, var.runner_ssm_token_arm64] : t.name if t != null],
    ))) == length(var.runner_pools) + length([for t in [var.runner_ssm_token_amd64, var.runner_ssm_token_arm64] : t if t != null])
    error_message = "Every runner pool needs its own token parameter, distinct from the other pools' and the per-architecture runners'."
  }
}
