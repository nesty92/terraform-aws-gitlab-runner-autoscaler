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

variable "aws_azs" {
  type    = list(string)
  default = []
}

variable "aws_vpc_id" {
  type = string
}

variable "aws_subnet_ids" {
  type = list(string)
}

variable "aws_security_group_ids" {
  type    = list(string)
  default = []
}

variable "aws_key_name" {
  type    = string
  default = ""
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
  EOT
  type = object({
    gitlab_check_interval     = optional(number, 3)
    maximum_concurrent_jobs   = optional(number, 10)
    prometheus_listen_address = optional(string, "")
    sentry_dsn                = optional(string, "")
  })
  default = {}
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
    ssm_access                  = optional(bool, false)
    type                        = optional(string, "t3.micro")
    use_eip                     = optional(bool, false)
    iam_instance_profile        = optional(string)
    security_group_ids          = optional(list(string), [])
  })
  default = null
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
    ssm_access                  = optional(bool, false)
    type                        = optional(string, "t4g.micro")
    use_eip                     = optional(bool, false)
    iam_instance_profile        = optional(string)
    security_group_ids          = optional(list(string), [])
  })
  default = null
  validation {
    condition     = var.runner_instance_arm64 != null || !contains(coalesce(var.architectures, []), "arm64")
    error_message = "runner_instance_arm64 is required when arm64 architecture is specified."
  }
}

variable "volume_size" {
  description = "The size of the root volume in GB."
  type        = number
  default     = 8
}

variable "cache_bucket_name" {
  description = "The name of the S3 bucket used for caching."
  type        = string
}

variable "access_key" {
  description = "The AWS access key ID."
  type        = string
}

variable "secret_key" {
  description = "The AWS secret access key."
  type        = string
}

