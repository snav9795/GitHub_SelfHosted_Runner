# Provider and Backend Configuration

provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "infra/terraform/github-runner-infra.json"
    region = "us-east-1"
  }

  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ECS Task Definition for GitHub Runner(s)
# For standalone: creates one task definition per repository
# For org: creates a single task definition

resource "aws_ecs_task_definition" "github_runner" {
  for_each = local.runners_map

  family       = "github-runner-task-def-${each.key}"
  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = var.default_task_execution_role

  container_definitions = jsonencode([
    {
      name      = "github-runner-container"
      image     = "XXXXXXXXXXXX.dkr.ecr.us-east-1.amazonaws.com/github-runner:terraform"
      essential = true

      portMappings = []

      entryPoint  = local.container_entrypoint
      command     = ["/home/runner/bin/runsvc.sh"]
      environment = each.value.environment

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = "awslogs-github-runner-${each.key}"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "github-runner"
        }
      }
    }
  ])

  tags = var.common_tags
}

# ECS Service for GitHub Runner(s)
# For standalone: creates one service per repository
# For org: creates a single service

resource "aws_ecs_service" "github_runner" {
  for_each = local.runners_map

  name            = "github-runner-${each.key}"
  cluster         = var.cluster_name
  desired_count   = 1
  task_definition = aws_ecs_task_definition.github_runner[each.key].arn

  platform_version    = "LATEST"
  scheduling_strategy = "REPLICA"

  network_configuration {
    subnets          = var.subnet_private_ids
    security_groups  = var.service_security_groups
    assign_public_ip = false
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  tags = var.common_tags
}

