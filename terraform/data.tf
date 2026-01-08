# Data sources for fetching secrets from AWS Parameter Store

# GitHub App Client ID (App ID)
data "aws_ssm_parameter" "github_app_client_id" {
  name = "/your-app-name/github-integration/client-id"
}

# GitHub App Installation ID
data "aws_ssm_parameter" "github_app_installation_id" {
  name = "/your-app-name/github-integration/installation-id"
}

# GitHub App Private Key (PEM format)
data "aws_ssm_parameter" "github_app_pem" {
  name            = "/your-app-name/github-integration/private-key"
  with_decryption = true
}

# GitHub Personal Access Token (for standalone runners)
data "aws_ssm_parameter" "github_pat" {
  name            = "/your-app-name/github-integration/pat"
  with_decryption = true
}

