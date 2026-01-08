# GitHub Self-Hosted Runner Infrastructure

Complete guide for deploying GitHub self-hosted runners on AWS ECS with dual-mode support.

## Overview

This infrastructure supports two types of GitHub self-hosted runners:

| Type | Authentication | Best For | Deployment |
|------|---------------|----------|------------|
| **Standalone** | Personal Access Token (PAT) | Specific repositories (one runner per repo) | Deploy multiple at once via CLI |
| **Organization** | GitHub App (Client ID + PEM) | Organization-wide (single runner for all repos) | Single org-level runner |

### Architecture

```
Standalone Mode:  PAT → Registration Token → Runner
Organization Mode: Client ID + PEM → JWT → Access Token → Registration Token → Runner
```

---

## 🔄 How GitHub Actions are Picked Up and Executed

### **Complete Workflow Execution Flow**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    GitHub Actions Execution Process                      │
└─────────────────────────────────────────────────────────────────────────┘

1. TRIGGER EVENT
   ├─ Push to repository
   ├─ Pull request created/updated
   ├─ Manual workflow_dispatch
   ├─ Scheduled (cron)
   └─ External webhook

        ↓

2. GITHUB EVALUATES WORKFLOW FILE (.github/workflows/*.yml)
   ├─ Parse YAML syntax
   ├─ Check triggers/conditions
   ├─ Identify runner requirements: runs-on: [self-hosted, corp_merch_runner]
   └─ Create job queue

        ↓

3. JOB QUEUING (GitHub's Job Queue)
   ├─ Job added to queue
   ├─ GitHub checks for available runners with matching labels
   └─ Status: "Queued" (yellow dot in GitHub UI)

        ↓

4. RUNNER POLLING (Every 2-3 seconds)
   ┌────────────────────────────────────────────────┐
   │ Self-Hosted Runner (in ECS Container)         │
   │                                                │
   │ While (true) {                                 │
   │   // Poll GitHub API for jobs                 │
   │   GET https://pipelines.actions.githubusercontent.com  │
   │                                                │
   │   If (job available && labels match) {        │
   │     Claim job                                  │
   │     Break polling loop                        │
   │   }                                            │
   │   Sleep 2-3 seconds                           │
   │ }                                              │
   └────────────────────────────────────────────────┘

        ↓

5. JOB ACQUISITION
   ├─ Runner claims the job
   ├─ GitHub marks job as "In Progress" (yellow spinner)
   ├─ Runner receives job payload with:
   │  ├─ Workflow steps
   │  ├─ Environment variables
   │  ├─ Secrets (encrypted)
   │  └─ Repository context
   └─ Creates isolated job workspace in /home/runner/_work/

        ↓

6. WORKSPACE PREPARATION
   ├─ Create job directory: /home/runner/_work/{repo-name}/{repo-name}
   ├─ Clone repository (if actions/checkout used)
   ├─ Set up environment variables
   ├─ Download and cache actions
   └─ Prepare job context

        ↓

7. STEP EXECUTION (Sequential)
   ┌────────────────────────────────────────────────┐
   │ For each step in workflow:                    │
   │                                                │
   │ Step 1: Checkout code                         │
   │   ├─ actions/checkout@v4                      │
   │   ├─ Clone repository                         │
   │   └─ Status: Running → Complete ✓             │
   │                                                │
   │ Step 2: Build application                     │
   │   ├─ Run: npm install                         │
   │   ├─ Stream logs to GitHub                    │
   │   └─ Status: Running → Complete ✓             │
   │                                                │
   │ Step 3: Run tests                             │
   │   ├─ Run: npm test                            │
   │   ├─ Capture exit code                        │
   │   └─ Status: Running → Complete ✓             │
   │                                                │
   │ Step N: Deploy                                │
   │   ├─ Run custom commands                      │
   │   └─ Status: Running → Complete ✓             │
   └────────────────────────────────────────────────┘

        ↓

8. LOG STREAMING (Real-time)
   ├─ Each command output → GitHub API
   ├─ Visible in GitHub Actions UI immediately
   ├─ STDOUT and STDERR captured
   └─ Timestamps added to each line

        ↓

9. JOB COMPLETION
   ├─ All steps executed
   ├─ Determine final status:
   │  ├─ Success (all steps exit 0) → Green check ✓
   │  ├─ Failure (any step non-zero exit) → Red X ✗
   │  └─ Cancelled (user stopped) → Grey circle ○
   ├─ Upload artifacts (if any)
   ├─ Send completion status to GitHub
   └─ Clean up workspace

        ↓

10. WORKSPACE CLEANUP
    ├─ Delete job directory
    ├─ Remove temporary files
    ├─ Preserve cache (if configured)
    └─ Runner returns to idle state

        ↓

11. RETURN TO POLLING
    ├─ Runner ready for next job
    ├─ Resume polling GitHub API
    └─ Cycle repeats
```

### **Runner Service Process (`runsvc.sh`)**

```bash
# Continuous loop running in the container
┌─────────────────────────────────────────────────┐
│ /home/runner/bin/runsvc.sh                     │
│                                                 │
│ while true; do                                  │
│   # 1. Connect to GitHub                       │
│   connect_to_github_api()                      │
│                                                 │
│   # 2. Send heartbeat (every 30 seconds)       │
│   send_heartbeat()                             │
│                                                 │
│   # 3. Poll for jobs (every 2-3 seconds)       │
│   poll_for_jobs() {                            │
│     if job_available():                        │
│       claim_job()                              │
│       execute_job()                            │
│       report_results()                         │
│   }                                             │
│                                                 │
│   # 4. Handle signals (SIGTERM, SIGINT)        │
│   trap cleanup EXIT                            │
│                                                 │
│   # 5. Sleep before next poll                  │
│   sleep 2                                       │
│ done                                            │
└─────────────────────────────────────────────────┘
```

### **Detailed Job Execution Inside Container**

```
Runner Container: github-runner-org-org (ECS Task)
│
├─ /home/runner/
│  ├─ bin/
│  │  └─ runsvc.sh              ← Main runner service (always running)
│  │
│  ├─ _work/                    ← Job workspaces
│  │  ├─ repo-name/
│  │  │  ├─ repo-name/          ← Cloned repository
│  │  │  │  ├─ .git/
│  │  │  │  ├─ src/
│  │  │  │  └─ package.json
│  │  │  └─ _temp/              ← Temporary files
│  │  │
│  │  └─ _actions/              ← Cached actions
│  │     ├─ actions/checkout/v4/
│  │     └─ actions/setup-node/v3/
│  │
│  ├─ .runner                   ← Runner configuration
│  └─ .credentials              ← OAuth token
```

### **Communication Flow**

```
┌──────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│                  │  Poll   │                  │ Queue   │                  │
│  Self-Hosted     │ ──────→ │  GitHub Actions  │ ←────── │   GitHub Repo    │
│  Runner (ECS)    │         │   Job Service    │         │   (Workflow)     │
│                  │         │                  │         │                  │
│  - Polls every   │ ←────── │  - Maintains     │ ──────→ │  - Triggers on   │
│    2-3 seconds   │ Job     │    job queue     │ Status  │    events        │
│  - Claims jobs   │ Data    │  - Matches       │ Updates │  - Creates jobs  │
│  - Executes      │         │    labels        │         │  - Shows status  │
│  - Reports back  │ ──────→ │  - Tracks        │         │                  │
│                  │ Logs    │    status        │         │                  │
└──────────────────┘         └──────────────────┘         └──────────────────┘
```

### **Job Matching Logic**

```yaml
# Workflow file specifies requirements
jobs:
  build:
    runs-on: [self-hosted, your-runner-label, linux]
    #         ↑           ↑                    ↑
    #         Required    Custom label         OS label

# Runner configuration (set during registration)
Runner Labels:
  - self-hosted         ← Automatic (all self-hosted runners)
  - Linux               ← Automatic (OS detection)
  - X64                 ← Automatic (architecture)
  - your-runner-label   ← Custom (set via --labels flag)

# GitHub Matching Algorithm:
# 1. Filter runners with "self-hosted" label
# 2. Filter runners with ALL required labels
# 3. Check runner is online and idle
# 4. Assign to first matching runner
```

### **Example: Complete Job Lifecycle**

```
Time    | Event                              | Runner State      | GitHub UI
--------|------------------------------------|--------------------|------------------
00:00   | Push to main branch                | Idle (polling)    | Workflow triggered
00:01   | Workflow parsed, job created       | Idle (polling)    | Job: Queued 🟡
00:02   | Runner polls, sees job             | Claiming job      | Job: Queued 🟡
00:03   | Runner claims job                  | Preparing         | Job: Running 🟡
00:04   | Checkout step starts               | Executing         | Step 1: Running
00:10   | Checkout complete                  | Executing         | Step 1: Complete ✓
00:11   | Build step starts                  | Executing         | Step 2: Running
00:35   | Build complete                     | Executing         | Step 2: Complete ✓
00:36   | Test step starts                   | Executing         | Step 3: Running
00:50   | Tests pass                         | Executing         | Step 3: Complete ✓
00:51   | Deploy step starts                 | Executing         | Step 4: Running
01:10   | Deploy complete                    | Finishing         | Step 4: Complete ✓
01:11   | Upload artifacts                   | Finalizing        | Uploading...
01:12   | Report success to GitHub           | Cleaning up       | Job: Success ✓ 🟢
01:13   | Clean workspace                    | Idle (polling)    | Workflow complete
01:14   | Resume polling for next job        | Idle (polling)    | -
```

### **Key Points**

1. **Continuous Polling**: Runner never stops polling GitHub (even when idle)
2. **Label Matching**: Jobs only go to runners with matching labels
3. **Serial Execution**: Runner handles one job at a time
4. **Real-time Logs**: All output streams to GitHub immediately
5. **Stateless Jobs**: Each job starts with clean workspace
6. **Automatic Cleanup**: Workspace cleaned after every job
7. **Heartbeat**: Runner sends periodic heartbeats to maintain connection
8. **Graceful Shutdown**: Finishes current job before stopping

### **Performance Characteristics**

| Metric | Value | Notes |
|--------|-------|-------|
| **Polling Interval** | 2-3 seconds | Configurable in runner config |
| **Job Claim Time** | < 1 second | From queue to claimed |
| **Workspace Setup** | 5-30 seconds | Depends on repo size |
| **Log Latency** | < 1 second | Real-time streaming |
| **Cleanup Time** | 2-5 seconds | After job completion |
| **Max Jobs/Hour** | ~30-60 | Depends on job duration |
| **Concurrent Jobs** | 1 per runner | Deploy multiple runners for parallel |

---

## File Structure

```
infrastructure/github-runner/
├── terraform/              # Infrastructure as Code
│   ├── main.tf            # ECS resources
│   ├── variables.tf       # Input variables
│   ├── locals.tf          # Conditional logic
│   ├── data.tf            # Parameter Store integration
│   └── outputs.tf         # Output values
├── docker/                # Container image
│   ├── Dockerfile
│   ├── entrypoint.sh      # Standalone runner
│   └── entrypoint-org.sh  # Organization runner
└── README.md              # This file
```

---

## Prerequisites

### Common Requirements
- AWS CLI configured
- Docker installed
- Terraform >= 1.0
- Access to AWS account (us-east-1)

### Credentials (Already Configured in Parameter Store)

**For Standalone Runners:**
- GitHub PAT stored at: `/your-app-name/github-integration/pat`

**For Organization Runners:**
- GitHub App Client ID at: `/your-app-name/github-integration/client-id`
- Installation ID at: `/your-app-name/github-integration/installation-id`
- Private Key at: `/your-app-name/github-integration/private-key`

---

## Complete Deployment Guide

### Step 1: Build and Push Docker Image

```bash
# Navigate to docker directory
cd infrastructure/github-runner/docker

# Build the image
docker build -t github-runner:terraform .

# Login to AWS ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  XXXXXXXXXXXX.dkr.ecr.us-east-1.amazonaws.com

# Tag the image
docker tag github-runner:terraform \
  XXXXXXXXXXXX.dkr.ecr.us-east-1.amazonaws.com/github-runner:terraform

# Push to ECR
docker push \
  XXXXXXXXXXXX.dkr.ecr.us-east-1.amazonaws.com/github-runner:terraform
```

### Step 2A: Deploy Standalone Runner(s) (PAT-based)

Standalone runners are deployed per repository. Default repository is pre-configured:

```bash
cd ../terraform

# Deploy runner for default repository (your-repository-name)
terraform init
terraform plan -var='runner_type=standalone'
terraform apply -var='runner_type=standalone'
```

**Deploy for Multiple Repositories (Optional Override):**
```bash
terraform apply \
  -var='runner_type=standalone' \
  -var='github_repository_name=["your-repository-name", "another-repo", "third-repo"]'
```

This will create:
- One ECS task definition per repository
- One ECS service per repository
- Separate CloudWatch log groups per repository

*Note: Default repository is `your-repository-name`. Override with `-var` if needed.*

*Prerequisites: PAT already stored in Parameter Store at `/your-app-name/github-integration/pat`*

**Verify:**
```
https://github.com/your-organization/your-repository-name/settings/actions/runners
```

### Step 2B: Deploy Organization Runner (GitHub App-based)

Organization runners are deployed at the org level (single runner):

```bash
cd terraform

# Deploy org-level runner
terraform init
terraform plan -var='runner_type=org'
terraform apply -var='runner_type=org'
```

This will create:
- One ECS task definition for the organization
- One ECS service for the organization
- Centralized CloudWatch log group

*Note: Runner will be registered to your-organization*

*Prerequisites: GitHub App credentials already stored in Parameter Store:*
- `/your-app-name/github-integration/client-id`
- `/your-app-name/github-integration/installation-id`
- `/your-app-name/github-integration/private-key`

**Verify:**
```
https://github.com/organizations/your-organization/settings/actions/runners
```

---

## Testing Your Runner

Create `.github/workflows/test-runner.yml` in your repository:

```yaml
name: Test Self-Hosted Runner

on: workflow_dispatch

jobs:
  test:
    runs-on: [self-hosted, your-runner-label]
    steps:
      - name: Check runner
        run: |
          echo "Running on: $(hostname)"
          echo "Runner name: $RUNNER_NAME"
          
      - name: Check tools
        run: |
          terraform --version
          aws --version
          docker --version
```

Run the workflow from GitHub Actions tab and verify success.

---

## Monitoring & Operations

### View Logs

```bash
# Standalone runner for specific repository
aws logs tail awslogs-github-runner-standalone-your-repository-name --follow

# Organization runner
aws logs tail awslogs-github-runner-org-org --follow

# All runners
aws logs tail awslogs-github-runner- --follow --filter-pattern ""
```

### Check ECS Service Status

```bash
# List running tasks
aws ecs list-tasks --cluster your-ecs-cluster-name

# Describe specific task
aws ecs describe-tasks \
  --cluster your-ecs-cluster-name \
  --tasks <task-arn>

# Check service status
aws ecs describe-services \
  --cluster your-ecs-cluster-name \
  --services github-runner-*
```

### Update Runner (New Docker Image)

```bash
# 1. Build and push new image (Step 1 above)

# 2. Force service update
cd terraform

# For specific standalone runner
terraform apply \
  -var='runner_type=standalone' \
  -var='github_repository_name=["your-repository-name"]' \
  -replace='aws_ecs_service.github_runner["your-repository-name"]'

# For org runner
terraform apply \
  -var='runner_type=org' \
  -replace='aws_ecs_service.github_runner["org"]'

# Or force all runners to update
terraform apply -replace='aws_ecs_service.github_runner'
```

### Scale Runners

```bash
# Update desired count in terraform/main.tf
# Change: desired_count = 1
# To:     desired_count = 3

terraform apply
```

---

## Troubleshooting

### Runner Not Appearing in GitHub

**Check logs:**
```bash
aws logs tail awslogs-github-runner- --follow --filter-pattern ""
```

**Common causes:**
- ❌ PAT expired or wrong scopes (standalone)
- ❌ Wrong Installation ID (org)
- ❌ PEM file format issue (org)
- ❌ Parameter Store values missing (org)
- ❌ Network connectivity (security groups)

### JWT Generation Failed (Org Runners)

```bash
# Verify PEM file format
openssl rsa -in github-app-private-key.pem -check

# Check Parameter Store values
aws ssm get-parameter \
  --name "/your-app-name/github-integration/private-key" \
  --with-decryption \
  --region us-east-1
```

### Runner Goes Offline

```bash
# Check task health
aws ecs describe-tasks \
  --cluster your-ecs-cluster-name \
  --tasks <task-arn>

# Review CloudWatch logs for errors
aws logs tail awslogs-github-runner- --follow --since 30m --filter-pattern ""
```

### Authentication Errors

**For Standalone:**
- Verify PAT has `repo` and `workflow` scopes
- Check PAT hasn't expired
- Ensure repository URL is correct

**For Organization:**
- Verify GitHub App has correct permissions
- Check Installation ID matches
- Ensure app is installed to your organization
- Verify Parameter Store values are correct

---

## Configuration Reference

### Automatic Configuration (Pre-configured)

| Setting | Value | Source |
|---------|-------|--------|
| **Runner name base** | `aws-github-runner` | Hardcoded |
| **Default repositories** | `your-repository-name` | Hardcoded (for standalone) |
| **Organization** | `https://github.com/your-organization` | Hardcoded |
| **Credentials** | All from Parameter Store | Auto-fetched |
| **Subnets** | 3 private subnets | Hardcoded |
| **Cluster** | `your-ecs-cluster-name` | Hardcoded |
| **Security Groups** | Pre-configured SG | Hardcoded |

*All values can be overridden via `-var` flags if needed*

### Required User Configuration

**Only one variable needed for both types:**

**Organization Runner:**
```bash
terraform apply -var='runner_type=org'
```

**Standalone Runner (uses default repo):**
```bash
terraform apply -var='runner_type=standalone'
```

**Standalone Runner (custom repositories - optional):**
```bash
terraform apply \
  -var='runner_type=standalone' \
  -var='github_repository_name=["repo1", "repo2", "repo3"]'
```

**What happens automatically:**
- ✅ Credentials fetched from Parameter Store
- ✅ For **standalone**: One runner per repository (default: your-repository-name)
- ✅ For **org**: Single organization-level runner
- ✅ Organization: your-organization (hardcoded)
- ✅ Infrastructure: All AWS resources pre-configured

### Parameter Store Keys (Pre-configured)

All credentials are already stored in AWS Parameter Store:

| Path | Type | Used By |
|------|------|---------|
| `/your-app-name/github-integration/client-id` | String | Org runners |
| `/your-app-name/github-integration/installation-id` | String | Org runners |
| `/your-app-name/github-integration/private-key` | SecureString | Org runners |
| `/your-app-name/github-integration/pat` | SecureString | Standalone runners |

---

## Security Best Practices

1. **Use Parameter Store** for all sensitive values (org runners do this automatically)
2. **Rotate credentials** regularly:
   - GitHub App keys: Every 6-12 months
   - PATs: Annually
3. **Never commit** secrets to version control:
   ```bash
   # Already in .gitignore:
   *.pem
   .terraform/
   terraform.tfstate*
   ```
4. **Use SecureString** type in Parameter Store
5. **Enable CloudTrail** for audit logging
6. **Limit IAM permissions** to minimum required

### Required IAM Permissions

ECS Task Execution Role needs:

```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:GetParameter",
    "ssm:GetParameters",
    "kms:Decrypt"
  ],
  "Resource": [
    "arn:aws:ssm:us-east-1:XXXXXXXXXXXX:parameter/your-app-name/github-integration/*",
    "arn:aws:kms:us-east-1:XXXXXXXXXXXX:key/*"
  ]
}
```

---

## Quick Command Reference

```bash
# Build and push image
cd docker && docker build -t github-runner:terraform . && \
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin XXXXXXXXXXXX.dkr.ecr.us-east-1.amazonaws.com && \
docker tag github-runner:terraform XXXXXXXXXXXX.dkr.ecr.us-east-1.amazonaws.com/github-runner:terraform && \
docker push XXXXXXXXXXXX.dkr.ecr.us-east-1.amazonaws.com/github-runner:terraform

# Deploy standalone (uses default repo)
cd terraform && terraform init && terraform apply -var='runner_type=standalone'

# Deploy org
cd terraform && terraform init && terraform apply -var='runner_type=org'

# View logs
aws logs tail awslogs-github-runner- --follow --filter-pattern ""

# Force restart
terraform apply -replace='aws_ecs_service.github_runner'

# Destroy
terraform destroy

# Check runner status in GitHub
# Standalone: https://github.com/your-organization/REPO/settings/actions/runners
# Org: https://github.com/organizations/your-organization/settings/actions/runners
```

---

## Cleanup

```bash
# Remove infrastructure
cd terraform

# For standalone (uses default repo)
terraform destroy -var='runner_type=standalone'

# For org
terraform destroy -var='runner_type=org'

# Remove from GitHub (automatic, but can be done manually)
# Visit: https://github.com/organizations/your-organization/settings/actions/runners
```

---

## Additional Resources

- [GitHub Actions Runner Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
- [GitHub Apps Documentation](https://docs.github.com/en/developers/apps)
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

## Support

For issues or questions:
1. Check CloudWatch logs first
2. Verify Parameter Store values (org runners)
3. Test GitHub App permissions
4. Review security group and network configuration
5. Consult troubleshooting section above

**Common Success Indicators:**
- ✅ Runner shows as "Idle" in GitHub UI
- ✅ ECS task status is "RUNNING"
- ✅ CloudWatch logs show successful registration
- ✅ Test workflow completes successfully
