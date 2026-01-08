# Terraform Configuration

This directory contains the Terraform infrastructure code for deploying GitHub self-hosted runners on AWS ECS.

## File Structure

```
terraform/
├── main.tf         # Main infrastructure resources (ECS tasks & services)
├── variables.tf    # Input variable definitions
├── locals.tf       # Local values and conditional logic
├── data.tf         # Parameter Store data sources
└── outputs.tf      # Output values
```

## File Descriptions

### `main.tf`
Contains the core infrastructure resources:
- AWS provider configuration
- Terraform backend (S3) configuration
- ECS Task Definitions (using `for_each` for multiple standalone runners)
- ECS Services to run and manage the runners

### `variables.tf`
Defines all input variables:
- **Infrastructure Variables**: Subnets, security groups, cluster name (all hardcoded with defaults)
- **Runner Type Configuration**: Standalone vs Organization
- **Runner Configuration**: Runner name (hardcoded), repository names (for standalone)
- **Organization URL**: Hardcoded to SyscoCorporation

### `locals.tf`
Contains local values for:
- Conditional environment variable configuration (standalone vs org)
- Container entrypoint selection
- Runners map (for_each iterator) for multiple standalone runners or single org runner

### `data.tf`
Fetches secrets from AWS Parameter Store:
- GitHub Personal Access Token (for standalone runners)
- GitHub App credentials (for org runners)

### `outputs.tf`
Exports useful values as maps:
- Service names and IDs (per repository/runner)
- Task definition ARNs and revisions (per repository/runner)
- CloudWatch log group names (per repository/runner)
- Runner type and cluster name

## Usage

### Initialize Terraform

```bash
cd terraform
terraform init
```

### Deploy Standalone Runners

Deploy runners for repositories (default: your-repository-name):

```bash
# Deploy with default repository
terraform apply -var='runner_type=standalone'

# Deploy for multiple repositories (optional override)
terraform apply \
  -var='runner_type=standalone' \
  -var='github_repository_name=["repo1", "repo2", "repo3"]'
```

This creates:
- One ECS task definition per repository
- One ECS service per repository
- Separate CloudWatch log groups per repository

### Deploy Organization Runner (Single)

Deploy a single org-level runner:

```bash
terraform apply -var='runner_type=org'
```

This creates:
- One ECS task definition for the organization
- One ECS service for the organization
- Centralized CloudWatch log group

### View Outputs

```bash
terraform output

# Example output:
# service_names = {
#   "your-repository-name" = "github-runner-standalone-your-repository-name"
#   "another-repo" = "github-runner-standalone-another-repo"
# }
```

### Destroy Infrastructure

```bash
# For standalone (uses default repo)
terraform destroy -var='runner_type=standalone'

# For org
terraform destroy -var='runner_type=org'

# For standalone with custom repos (must match what was deployed)
terraform destroy \
  -var='runner_type=standalone' \
  -var='github_repository_name=["repo1", "repo2"]'
```

## Required Variables

### For Both Runner Types:
- `runner_type` = "standalone" or "org" (via CLI)

### Pre-configured (Hardcoded with Defaults):
- `github_runner_name` = "aws-github-runner"
- `github_repository_name` = ["your-repository-name"] (for standalone, can be overridden)
- `github_organization_url` = "https://github.com/your-organization"
- `subnet_private_ids` = [3 private subnets]
- `cluster_name` = "your-ecs-cluster-name"
- `service_security_groups` = ["sg-xxxxxxxxxxxxxxxxx"]

### Fetched from Parameter Store:
- GitHub PAT (for standalone runners)
- GitHub App credentials (for org runners)

## Backend Configuration

The Terraform state is stored in S3:
- **Bucket**: `your-terraform-state-bucket`
- **Key**: `infra/terraform/github-runner-infra.json`
- **Region**: `us-east-1`

To use a different backend, modify the `backend` block in `main.tf`.

## Resource Naming

Resources are named using a consistent pattern:

**For Standalone Runners:**
- **Task Definition**: `github-runner-task-def-standalone-{repo_name}`
- **Service**: `github-runner-standalone-{repo_name}`
- **Log Group**: `awslogs-github-runner-standalone-{repo_name}`

**For Organization Runners:**
- **Task Definition**: `github-runner-task-def-org-org`
- **Service**: `github-runner-org-org`
- **Log Group**: `awslogs-github-runner-org-org`

## Tags

All resources are tagged with:
- `Name`: Resource-specific name
- `RunnerType`: standalone or org
- `Repository`: Repository name (for standalone runners)
- `Environment`: production
- `ManagedBy`: terraform

## Validation

The configuration includes validation rules:
- `runner_type` must be either "standalone" or "org"
- For standalone runners, `github_repository_name` list must not be empty
- Sensitive values (PAT, PEM) are fetched from Parameter Store with encryption

## Best Practices

1. **Pass variables via CLI** - No tfvars files needed; variables passed via `-var` flags
2. **Use Parameter Store for secrets** - All credentials fetched from AWS Parameter Store
3. **Deploy multiple standalone runners** - Pass a list of repositories to deploy runners for all at once
4. **Review plan output** before applying changes
5. **Use remote state** (already configured with S3)
6. **Keep repository names consistent** - Use the same list when updating/destroying

## Troubleshooting

### State Lock Issues
```bash
# Force unlock if needed (use with caution)
terraform force-unlock <lock-id>
```

### Validate Configuration
```bash
terraform validate
```

### Format Code
```bash
terraform fmt -recursive
```

### View Current State
```bash
terraform show
```

## Migration from Old Structure

**Important:** This version uses `for_each` for resources, which changes resource addresses.

### If migrating from previous version:

1. **Resource names have changed** due to `for_each` implementation
2. Old: `aws_ecs_service.github_runner`
3. New: `aws_ecs_service.github_runner["repo-name"]` or `aws_ecs_service.github_runner["org"]`

### Migration Steps:

```bash
# Option 1: Destroy old and recreate (recommended for clean state)
terraform destroy  # using old configuration
terraform apply -var='runner_type=standalone' -var='github_repository_name=["repo1"]'

# Option 2: Import existing resources (advanced)
# Import task definition and service with new keys
terraform import 'aws_ecs_task_definition.github_runner["repo1"]' github-runner-task-def-standalone-repo1
terraform import 'aws_ecs_service.github_runner["repo1"]' your-ecs-cluster-name/github-runner-standalone-repo1
```
