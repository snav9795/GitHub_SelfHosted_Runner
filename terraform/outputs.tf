# Outputs

output "service_names" {
  description = "Map of repository/runner names to ECS service names"
  value       = { for k, v in aws_ecs_service.github_runner : k => v.name }
}

output "service_ids" {
  description = "Map of repository/runner names to ECS service IDs"
  value       = { for k, v in aws_ecs_service.github_runner : k => v.id }
}

output "task_definition_arns" {
  description = "Map of repository/runner names to task definition ARNs"
  value       = { for k, v in aws_ecs_task_definition.github_runner : k => v.arn }
}

output "task_definition_families" {
  description = "Map of repository/runner names to task definition families"
  value       = { for k, v in aws_ecs_task_definition.github_runner : k => v.family }
}

output "task_definition_revisions" {
  description = "Map of repository/runner names to task definition revisions"
  value       = { for k, v in aws_ecs_task_definition.github_runner : k => v.revision }
}

output "log_group_names" {
  description = "Map of repository/runner names to CloudWatch log group names"
  value       = { for k in keys(local.runners_map) : k => "awslogs-github-runner-${var.runner_type}-${k}" }
}

output "runner_type" {
  description = "Type of runner deployed (standalone or org)"
  value       = var.runner_type
}

output "cluster_name" {
  description = "ECS cluster where the runner is deployed"
  value       = var.cluster_name
}

output "deployed_runners" {
  description = "List of deployed runner repository names"
  value       = keys(local.runners_map)
}

