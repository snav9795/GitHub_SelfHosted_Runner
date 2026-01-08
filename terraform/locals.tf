# Local values for conditional environment variable configuration

locals {
  # Select entrypoint based on runner type
  container_entrypoint = var.runner_type == "org" ? ["/entrypoint-org.sh"] : ["/entrypoint.sh"]

  # Organization runner configuration (single runner)
  org_runner_config = var.runner_type == "org" ? {
    "org" = {
      environment = [
        {
          "name" : "GITHUB_APP_CLIENT_ID",
          "value" : data.aws_ssm_parameter.github_app_client_id.value
        },
        {
          "name" : "GITHUB_APP_PEM",
          "value" : data.aws_ssm_parameter.github_app_pem.value
        },
        {
          "name" : "GITHUB_APP_INSTALLATION_ID",
          "value" : data.aws_ssm_parameter.github_app_installation_id.value
        },
        {
          "name" : "RUNNER_NAME",
          "value" : var.github_runner_name
        },
        {
          "name" : "RUNNER_ORGANIZATION_URL",
          "value" : var.github_organization_url
        }
      ]
    }
  } : {}

  # Standalone runner configuration (one per repository)
  standalone_runner_config = var.runner_type == "standalone" ? {
    for repo_name in var.github_repository_name : repo_name => {
      environment = [
        {
          "name" : "GITHUB_ACCESS_TOKEN",
          "value" : data.aws_ssm_parameter.github_pat.value
        },
        {
          "name" : "RUNNER_NAME",
          "value" : "${var.github_runner_name}-${repo_name}"
        },
        {
          "name" : "RUNNER_REPOSITORY_URL",
          "value" : "${var.github_organization_url}/${repo_name}"
        }
      ]
    }
  } : {}

  # Merge configurations based on runner type
  runners_map = var.runner_type == "org" ? local.org_runner_config : local.standalone_runner_config
}

