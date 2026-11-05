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

variable "job_variables" {
  description = <<-EOT
    Variables set on every job the runners take, through each [[runners]] entry's environment. The runner, not GitLab,
    expands image and services names, so these can name a job's image: image: $DOCKER_HUB_CACHE/library/golang:1.25.
    A CI/CD variable of the same name, from the project, the group or .gitlab-ci.yml, wins over these.
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for key in keys(var.job_variables) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", key))])
    error_message = "Each job_variables key must be a variable name: letters, digits and underscores, not starting with a digit."
  }

  validation {
    condition     = !contains(keys(var.job_variables), "DOCKER_AUTH_CONFIG")
    error_message = "DOCKER_AUTH_CONFIG is the module's to set, through ecr_job_images."
  }
}

variable "runner_cache" {
  description = <<-EOT
    A cache that the jobs of every runner share ([runners.cache]). Null keeps each instance's local cache. The backend
    is S3, the one this AWS module can grant its own role to: the Manager signs every upload and download with that
    role, so neither the instances nor the jobs hold a credential. The bucket is the consumer's, and so is its cleanup:
    give it a lifecycle rule that expires caches no job has written for a while.

    path                      = A prefix every cache key is written under. Empty writes at the bucket's root.
    shared                    = One cache for all the runners, rather than one per runner. Defaults to true.
    max_uploaded_archive_size = The largest cache archive a job may upload, in bytes. A larger one is not uploaded.
                                0 sets no limit.
    s3 = {
      bucket_name                   = The S3 bucket the caches are kept in.
      bucket_region                 = The bucket's region. Defaults to the module's region.
      server_side_encryption        = "S3", "KMS" or "DSSE-KMS". Null leaves it to the bucket's default encryption.
      server_side_encryption_key_id = The KMS key ARN for "KMS" or "DSSE-KMS". The Manager's role may use it.
      dual_stack                    = Use S3's dual-stack endpoint, the runner's default. false keeps the jobs on the
                                      regional IPv4 endpoint.
    }
  EOT
  type = object({
    path                      = optional(string, "")
    shared                    = optional(bool, true)
    max_uploaded_archive_size = optional(number, 0)
    s3 = object({
      bucket_name                   = string
      bucket_region                 = optional(string)
      server_side_encryption        = optional(string)
      server_side_encryption_key_id = optional(string)
      dual_stack                    = optional(bool)
    })
  })
  default = null

  validation {
    condition     = var.runner_cache == null ? true : try(length(trimspace(var.runner_cache.s3.bucket_name)) > 0, false)
    error_message = "runner_cache.s3.bucket_name must name a bucket."
  }

  validation {
    condition     = var.runner_cache == null ? true : try(var.runner_cache.max_uploaded_archive_size >= 0 && floor(var.runner_cache.max_uploaded_archive_size) == var.runner_cache.max_uploaded_archive_size, false)
    error_message = "runner_cache.max_uploaded_archive_size is a whole number of bytes, 0 for no limit."
  }

  validation {
    condition     = var.runner_cache == null ? true : (var.runner_cache.s3.server_side_encryption == null ? true : contains(["S3", "KMS", "DSSE-KMS"], var.runner_cache.s3.server_side_encryption))
    error_message = "runner_cache.s3.server_side_encryption is \"S3\", \"KMS\", \"DSSE-KMS\" or null."
  }

  validation {
    condition = var.runner_cache == null ? true : (
      contains(["KMS", "DSSE-KMS"], coalesce(var.runner_cache.s3.server_side_encryption, "none"))
      == (var.runner_cache.s3.server_side_encryption_key_id != null)
    )
    error_message = "runner_cache.s3.server_side_encryption_key_id is set with \"KMS\" or \"DSSE-KMS\", and only then."
  }
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
  description = "Configuration for the AMD64 GitLab Runner instance. Required when amd64 architecture is specified. subnet_ids, when set, are the subnets its Auto Scaling group launches into; unset, it uses aws_subnet_ids."
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
    subnet_ids           = optional(list(string))
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

  validation {
    condition     = var.runner_instance_amd64 == null ? true : (var.runner_instance_amd64.subnet_ids == null ? true : length(var.runner_instance_amd64.subnet_ids) > 0)
    error_message = "subnet_ids, when set, must name at least one subnet."
  }
}

variable "runner_instance_arm64" {
  description = "Configuration for the ARM64 GitLab Runner instance. Required when arm64 architecture is specified. subnet_ids, when set, are the subnets its Auto Scaling group launches into; unset, it uses aws_subnet_ids."
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
    subnet_ids           = optional(list(string))
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

  validation {
    condition     = var.runner_instance_arm64 == null ? true : (var.runner_instance_arm64.subnet_ids == null ? true : length(var.runner_instance_arm64.subnet_ids) > 0)
    error_message = "subnet_ids, when set, must name at least one subnet."
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
    builds_dir = An absolute [[runners]] builds_dir. Unset, the runner's own default applies. The instance executor's default is
      relative, and a relative builds directory breaks the runner's cache upload, which resolves its temporary files
      against the project directory; give an instance pool that uses runner_cache an absolute one.
    cache_dir = An absolute [[runners]] cache_dir, where the runner keeps a job's cache archive on the instance. The runner
      refuses to use the cache when one of builds_dir and cache_dir is absolute and the other relative, as the instance
      executor's default cache_dir is; set both, or neither.
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
    builds_dir       = optional(string)
    cache_dir        = optional(string)
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

  validation {
    condition     = alltrue([for pool in values(var.runner_pools) : pool.builds_dir == null ? true : startswith(pool.builds_dir, "/")])
    error_message = "builds_dir must be an absolute path."
  }

  validation {
    condition     = alltrue([for pool in values(var.runner_pools) : pool.cache_dir == null ? true : startswith(pool.cache_dir, "/")])
    error_message = "cache_dir must be an absolute path."
  }

  validation {
    condition     = alltrue([for pool in values(var.runner_pools) : (pool.builds_dir == null) == (pool.cache_dir == null)])
    error_message = "Set builds_dir and cache_dir together: the runner skips the cache when one is absolute and the other relative."
  }
}

variable "fleetci" {
  description = <<-EOT
    Opt-in per-job VM classes with fleetci (https://github.com/nesty92/fleetci). A job names the size it needs and
    gets a fresh VM of that size, used once: on GitLab with `extends: .fleetci-<class>` (see the fleetci output's
    ci_include), on GitHub Actions with `runs-on: fleetci-<class>`. Left null (the default), nothing changes.

    The Manager installs fleetci at boot, writes /etc/fleetci/fleetci.toml from classes, adds a runner-fleetci
    [[runners]] entry (with runner_cache, job_variables and feature_flags, like the other runners) and logs
    `fleetci check`. Changing anything here replaces the Manager, as a runner pool change does.

    version = fleetci release to install.
    token = The SSM parameter holding the runner authentication token of a runner registered with the tag `tag`
      (and "Run untagged jobs" off).
    tag = That runner's tag, which the fleetci output's ci_include sets (default fleetci).
    on_invalid_token = skip (default): a missing or invalid token leaves fleetci out of config.toml; fail: the
      Manager's boot exits.
    default_class = The class a job gets when it names none.
    classes = One Auto Scaling group each (gitlab-runner-fleetci-<class>-asg), on spot, in private subnets:
      architecture = amd64 (default) or arm64.
      instance_types = The types the group may launch; more than one makes it a mixed instances policy. Prefer
        non-burstable types (c7a, c7i, m7i, m7g): a T type (t3, t3a, t4g) bills surplus CPU credits for
        a CPU-bound job, and in standard mode starts with no credits, throttled to its baseline.
      max_instances = The most VMs at once (default 4); a ceiling, nothing runs until a job needs it.
      ami_id = The class's image, built with packer/fleetci/fleetci.pkr.hcl (Ubuntu 24.04 with Docker and actions/runner),
        one per architecture. Its own build needs Docker, the connector's user in the docker group, EC2 Instance
        Connect and, for GitHub jobs, libicu and actions/runner in ~/actions-runner-<github_runner_version>.
      user_data = Run on each VM's boot, for what the image lacks; none by default.
      username = The SSH user fleetci logs in as (default ubuntu).
      volume_size = Root volume GiB (default 30).
      acquire_timeout = How long a job waits for a VM (default 10m).
      policy = Warm VMs by time of day, as runner_autoscaler_policy_amd64. Empty (default): every VM boots for its job.
      subnet_ids = Defaults to aws_subnet_ids.
      private_address_only = false gives each VM a public IPv4 ($0.005/h), for public subnets without a NAT
        gateway, whose data charge every image pull of a fresh VM pays. The Manager still connects privately.
      spot_allocation_strategy = As runner_instance_amd64's.
    docker = [runners.docker] options for fleetci's runner; default image ubuntu:24.04.
    github = GitHub Actions jobs on the same classes: repos as owner/name, and the SSM parameter holding a
      fine-grained token with Actions: Read and Administration: Read and write on them.
    github_runner_version = actions/runner release GitHub jobs run: the one packer/fleetci/fleetci.pkr.hcl unpacked
      (its runner_version), else it is downloaded for each job.
    watchdog = true (default) runs `fleetci watchdog` beside gitlab-runner, which never starts a dead fleeting
      plugin again: if fleetci's plugin dies, every class on GitLab and GitHub stops until gitlab-runner restarts.
      The watchdog restarts gitlab-runner once the plugin has been gone for 30 s, which also ends the jobs of the
      Manager's other runner pools. Needs fleetci 0.3.0 or later; with an older version the Manager logs that
      and runs without it.

    concurrent (runner_manager.maximum_concurrent_jobs) is raised by the sum of the classes' max_instances.
  EOT

  type = object({
    version = optional(string, "0.3.0")
    token = object({
      name   = string
      arn    = string
      region = string
    })
    on_invalid_token = optional(string, "skip")
    tag              = optional(string, "fleetci")
    default_class    = string
    classes = map(object({
      architecture             = optional(string, "amd64")
      instance_types           = list(string)
      max_instances            = optional(number, 4)
      ami_id                   = string
      user_data                = optional(string)
      username                 = optional(string, "ubuntu")
      volume_size              = optional(number, 30)
      acquire_timeout          = optional(string)
      subnet_ids               = optional(list(string))
      private_address_only     = optional(bool, true)
      spot_allocation_strategy = optional(string, "price-capacity-optimized")
      policy = optional(list(object({
        periods            = optional(list(string))
        timezone           = optional(string)
        idle_count         = optional(number)
        idle_time          = optional(string)
        scale_factor       = optional(number)
        scale_factor_limit = optional(number)
      })), [])
    }))
    docker = optional(any, { image = "ubuntu:24.04" })
    github = optional(object({
      repos = list(string)
      token = object({
        name   = string
        arn    = string
        region = string
      })
    }))
    github_runner_version = optional(string, "2.338.2")
    watchdog              = optional(bool, true)
  })
  default = null

  validation {
    condition     = var.fleetci == null ? true : length(var.fleetci.classes) > 0 && contains(keys(var.fleetci.classes), var.fleetci.default_class)
    error_message = "fleetci needs at least one class, and default_class must be one of them."
  }

  validation {
    condition     = var.fleetci == null ? true : alltrue([for k in keys(var.fleetci.classes) : can(regex("^[a-z0-9][a-z0-9-]{0,29}$", k))])
    error_message = "fleetci class names must match ^[a-z0-9][a-z0-9-]{0,29}$, such as 2vcpu-4gb."
  }

  validation {
    condition     = var.fleetci == null ? true : alltrue([for c in values(var.fleetci.classes) : contains(["amd64", "arm64"], c.architecture) && length(c.instance_types) > 0 && c.max_instances >= 1])
    error_message = "Each fleetci class needs architecture amd64 or arm64, at least one instance type and max_instances of at least 1."
  }

  validation {
    condition     = var.fleetci == null ? true : alltrue([for c in values(var.fleetci.classes) : contains(["price-capacity-optimized", "capacity-optimized", "capacity-optimized-prioritized", "lowest-price"], c.spot_allocation_strategy)])
    error_message = "spot_allocation_strategy must be price-capacity-optimized, capacity-optimized, capacity-optimized-prioritized or lowest-price."
  }

  validation {
    condition     = var.fleetci == null ? true : contains(["skip", "fail"], var.fleetci.on_invalid_token)
    error_message = "fleetci.on_invalid_token must be skip or fail."
  }

  validation {
    condition     = var.fleetci == null ? true : alltrue([for k in keys(var.fleetci.classes) : !contains(keys(var.runner_pools), "fleetci-${k}")])
    error_message = "A runner_pools key equals fleetci-<class> for a fleetci class; both would name the same Auto Scaling group."
  }

  validation {
    condition     = var.fleetci == null ? true : (var.fleetci.github == null ? true : alltrue([for r in var.fleetci.github.repos : can(regex("^[^/]+/[^/]+$", r))]))
    error_message = "fleetci.github.repos must be owner/name."
  }
}
