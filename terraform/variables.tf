# Infrastructure Variables

variable "subnet_private_ids" {
  type        = list(string)
  description = "The ids of the private subnets for the ECS containers"
  default = [
    "subnet-xxxxxxxxxxxxxxxxx",
    "subnet-yyyyyyyyyyyyyyyyy",
    "subnet-zzzzzzzzzzzzzzzzz"
  ]
}

variable "default_task_execution_role" {
  type        = string
  description = "Default task execution role for ECS tasks"
  default     = "arn:aws:iam::XXXXXXXXXXXX:role/ecs-task-execution-role"
}

variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster to deploy the runner service"
  default     = "your-ecs-cluster-name"
}

variable "service_security_groups" {
  type        = list(string)
  description = "List of security groups to be used by the ECS service"
  default     = ["sg-xxxxxxxxxxxxxxxxx"]
}

# Runner Type Configuration

variable "runner_type" {
  type        = string
  description = "Type of runner: 'standalone' for PAT-based repo runners, 'org' for GitHub App-based org runners"
  default     = "standalone"
  validation {
    condition     = contains(["standalone", "org"], var.runner_type)
    error_message = "runner_type must be either 'standalone' or 'org'."
  }
}

# Runner Configuration

variable "github_runner_name" {
  type        = string
  description = "Name of the GitHub runner"
  default     = "aws-github-runner"
}

variable "github_repository_name" {
  type        = list(string)
  description = "List of repository names (for standalone mode, one runner per repo). For org mode, this is ignored."
  default = [
    "your-repository-name"
  ]
  validation {
    condition     = var.runner_type == "org" || length(var.github_repository_name) > 0
    error_message = "For standalone runner_type, github_repository_name list must contain at least one repository name."
  }
}

variable "github_organization_url" {
  type        = string
  description = "URL of the organization to which the runner would be registered (can be used with standalone or org mode)"
  default     = "https://github.com/your-organization"
}

# Common Tags for all resources
variable "common_tags" {
  type        = map(string)
  description = "Common tags to be applied to all resources"
  default = {
    "Technical:ApplicationID"     = "APP-XXXXXX"
    "Technical:ApplicationName"   = "Your Application Name"
    "Technical:PlatformOwner"     = "owner@example.com"
    "Technical:PatchingOwner"     = "TEAM"
    "cloud_supportteam"           = "your-team"
  }
}

