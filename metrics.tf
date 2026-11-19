# The Manager's metrics, shipped by a Prometheus in agent mode on it to a
# remote-write endpoint (runner_manager.metrics): gitlab-runner's own, and
# each fleetci runner's, which say how each job fit its class.

locals {
  metrics = var.runner_manager.metrics

  # gitlab-runner serves its metrics where it is told; shipping them needs an
  # address, so 127.0.0.1:9252 (its usual port) when none is set.
  gitlab_runner_listen = (
    var.runner_manager.prometheus_listen_address != "" ? var.runner_manager.prometheus_listen_address :
    local.metrics != null ? "127.0.0.1:9252" : ""
  )

  # A listen address's port, scraped on 127.0.0.1 whatever it listens on.
  metrics_targets = {
    gitlab_runner = local.gitlab_runner_listen == "" ? null : format("127.0.0.1:%s", regex("[0-9]+$", local.gitlab_runner_listen))
    fleetci = {
      for key, listen in local.fleetci_metrics_listen : key => format("127.0.0.1:%s", regex("[0-9]+$", listen)) if listen != null
    }
  }

  prometheus_agent = local.metrics == null ? null : {
    version = trimprefix(local.metrics.prometheus_version, "v")
    config = yamlencode({
      global = {
        scrape_interval = local.metrics.scrape_interval
        external_labels = merge({ runner_manager = format("gitlab-runner-manager-%s", var.environment) }, local.metrics.external_labels)
      }
      scrape_configs = concat(
        [
          {
            job_name       = "gitlab-runner"
            static_configs = [{ targets = [local.metrics_targets.gitlab_runner] }]
          },
          {
            job_name       = "prometheus-agent"
            static_configs = [{ targets = ["127.0.0.1:9095"] }]
          },
        ],
        length(local.metrics_targets.fleetci) == 0 ? [] : [
          {
            job_name = "fleetci"
            static_configs = [
              for key in sort(keys(local.metrics_targets.fleetci)) : {
                targets = [local.metrics_targets.fleetci[key]]
                labels  = { runner = format("runner-%s", key) }
              }
            ]
          },
        ],
      )
      remote_write = [
        merge(
          { url = local.metrics.remote_write.url },
          local.metrics.remote_write.sigv4_region == null ? {} : { sigv4 = { region = local.metrics.remote_write.sigv4_region } },
        )
      ]
    })
  }
}

# Write to the Amazon Managed Service for Prometheus workspace named in
# runner_manager.metrics.
resource "aws_iam_role_policy" "metrics_remote_write" {
  count = try(local.metrics.remote_write.workspace_arn, null) == null ? 0 : 1

  name = format("gitlab-runner-manager-metrics-%s", var.environment)
  role = aws_iam_role.runner_manager.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "ShipTheManagersMetrics"
        Effect   = "Allow"
        Action   = "aps:RemoteWrite"
        Resource = local.metrics.remote_write.workspace_arn
      },
    ]
  })
}

