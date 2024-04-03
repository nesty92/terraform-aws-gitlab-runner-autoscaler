output "runner_manager_id" {
  value = aws_instance.runner_manager.id
}

output "auto_scaling_group_ids" {
  value = [for asg in aws_autoscaling_group.gitlab_runner_instance : asg.id]
}

output "launch_template_ids" {
  value = [for lt in aws_launch_template.gitlab_runner_instance : lt.id]
}
