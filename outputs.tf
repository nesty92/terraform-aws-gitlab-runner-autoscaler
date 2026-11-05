output "runner_manager_id" {
  value = aws_instance.runner_manager.id
}

output "auto_scaling_group_ids" {
  value = [for asg in aws_autoscaling_group.gitlab_runner_instance : asg.id]
}

output "launch_template_ids" {
  value = [for lt in aws_launch_template.gitlab_runner_instance : lt.id]
}

output "pools" {
  description = "Every runner pool, the per-architecture ones included, keyed as in config.toml: its Auto Scaling group, launch template and runner name."
  value = {
    for key in concat(var.architectures, local.pool_keys) : key => {
      asg_name           = aws_autoscaling_group.gitlab_runner_instance[key].name
      asg_arn            = aws_autoscaling_group.gitlab_runner_instance[key].arn
      launch_template_id = aws_launch_template.gitlab_runner_instance[key].id
      runner_name        = format("runner-%s", key)
    }
  }
}

output "runner_security_group_id" {
  description = "The security group every runner instance carries, which admits SSH and WinRM from the Runner Manager."
  value       = aws_security_group.runner.id
}

output "runner_manager_security_group_id" {
  description = "The Runner Manager's security group."
  value       = aws_security_group.runner_manager.id
}

output "runner_manager_role_name" {
  description = "The Runner Manager's IAM role, for a consumer that must attach a policy of its own."
  value       = aws_iam_role.runner_manager.name
}

output "fleetci" {
  description = "Per runner pool with fleetci: its runner name, default class, each class's Auto Scaling group and GitHub label, and ci_include, a GitLab CI include to commit as .gitlab/fleetci.yml (jobs pick a class with extends: .fleetci-<class>; fleetci's public template does the same for its standard classes). Null when no pool has fleetci."
  value = length(local.fleetci_pools) == 0 ? null : {
    for key, pool in local.fleetci_pools : key => {
      runner_name   = format("runner-%s", key)
      default_class = pool.fleetci.class
      classes = {
        for name in keys(local.fleetci_pool_classes[key]) : name => {
          asg_name           = aws_autoscaling_group.gitlab_runner_instance[name == pool.fleetci.class ? key : format("%s-%s", key, name)].name
          asg_arn            = aws_autoscaling_group.gitlab_runner_instance[name == pool.fleetci.class ? key : format("%s-%s", key, name)].arn
          launch_template_id = aws_launch_template.gitlab_runner_instance[name == pool.fleetci.class ? key : format("%s-%s", key, name)].id
          github_label       = format("fleetci-%s", name)
        }
      }
      ci_include = join("\n", [
        format("# fleetci classes of runner %s (tag fleetci). Default class: %s.", format("runner-%s", key), pool.fleetci.class),
        "#   extends: .fleetci           # the default class",
        "#   extends: .fleetci-<class>   # one of the classes below",
        yamlencode(merge(
          { ".fleetci" = { tags = ["fleetci"] } },
          { for name in keys(local.fleetci_pool_classes[key]) : ".fleetci-${name}" => { extends = ".fleetci", variables = { FLEETCI_CLASS = name } } },
        )),
      ])
    }
  }
}
