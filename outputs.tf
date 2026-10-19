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
    for key in local.pool_order : key => {
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
