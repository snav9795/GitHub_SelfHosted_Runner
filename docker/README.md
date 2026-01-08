# GitHub Runner Docker Image - Registration Flow

This directory contains the Docker image configuration for GitHub Actions self-hosted runners with support for both repository-level and organization-level registration.

## 📂 File Structure

```
docker/
├── Dockerfile              # Container image definition
├── entrypoint.sh           # Standalone (repository-level) runner entrypoint
├── entrypoint-org.sh       # Organization-level runner entrypoint
├── supervisord.conf        # Process supervisor configuration
└── README.md              # This file
```

## 🔄 Two Registration Methods

### Method 1: **Standalone (Repository-Level) Runner** 
**Uses**: `entrypoint.sh`  
**Authentication**: Personal Access Token (PAT)  
**Registers to**: Specific repository

### Method 2: **Organization-Level Runner**
**Uses**: `entrypoint-org.sh`  
**Authentication**: GitHub App (Client ID + Private Key)  
**Registers to**: Entire organization

---

## 🎯 Standalone Runner Registration Flow (`entrypoint.sh`)

### **Architecture**
```
┌─────────────────────────────────────────────────────────────┐
│                  Standalone Runner Flow                      │
└─────────────────────────────────────────────────────────────┘

Container Start
    ↓
┌─────────────────────────────────────┐
│ 1. Environment Variables            │
│    - GITHUB_ACCESS_TOKEN (PAT)      │
│    - RUNNER_REPOSITORY_URL          │
│    - RUNNER_NAME                    │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 2. Check .runner File               │
│    Exists? → Skip to step 5         │
│    Missing? → Continue               │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 3. Get Registration Token           │
│    POST: /repos/{owner}/{repo}/     │
│          actions/runners/           │
│          registration-token         │
│    Auth: token {PAT}                │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 4. Configure Runner                 │
│    ./config.sh                      │
│      --url {REPO_URL}               │
│      --token {REGISTRATION_TOKEN}   │
│      --name {RUNNER_NAME}           │
│      --labels your-runner-label     │
│      --unattended                   │
│    Creates: .runner file            │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 5. Start Runner Service             │
│    exec /home/runner/bin/runsvc.sh  │
└─────────────────────────────────────┘
```

### **Required Environment Variables**

| Variable | Description | Example |
|----------|-------------|---------|
| `GITHUB_ACCESS_TOKEN` | Personal Access Token with `repo` scope | `ghp_xxxxxxxxxxxx` |
| `RUNNER_REPOSITORY_URL` | Full URL to repository | `https://github.com/your-organization/my-repo` |
| `RUNNER_NAME` | Name for the runner | `aws-github-runner-my-repo` |
| `RUNNER_WORK_DIRECTORY` | Working directory (optional) | `_work` (default) |
| `RUNNER_REPLACE_EXISTING` | Replace existing runner (optional) | `true` (default) |
| `RUNNER_LABELS` | Custom labels (optional) | `your-runner-label` |

### **Authentication Details**

**PAT (Personal Access Token):**
- **Scopes Required**: `repo`, `workflow`
- **Security**: Stored in AWS Parameter Store
- **Lifetime**: User-defined (recommend annual rotation)
- **Direct Exchange**: PAT → Registration Token (single API call)

### **API Endpoints Used**

```bash
# Get registration token
POST https://api.github.com/repos/{owner}/{repo}/actions/runners/registration-token
Authorization: token {GITHUB_ACCESS_TOKEN}

# Response
{
  "token": "ABCDEF...",
  "expires_at": "2024-01-01T12:00:00Z"
}
```

### **Example Usage**

```bash
docker run -d \
  -e GITHUB_ACCESS_TOKEN="ghp_xxxxx" \
  -e RUNNER_REPOSITORY_URL="https://github.com/your-organization/my-repo" \
  -e RUNNER_NAME="aws-github-runner-my-repo" \
  github-runner:terraform
```

---

## 🏢 Organization-Level Runner Registration Flow (`entrypoint-org.sh`)

### **Architecture**

```
┌─────────────────────────────────────────────────────────────┐
│              Organization Runner Flow                        │
└─────────────────────────────────────────────────────────────┘

Container Start
    ↓
┌─────────────────────────────────────┐
│ 1. Environment Variables            │
│    - GITHUB_APP_CLIENT_ID           │
│    - GITHUB_APP_PEM                 │
│    - GITHUB_APP_INSTALLATION_ID     │
│    - RUNNER_ORGANIZATION_URL        │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 2. Check .runner File               │
│    Exists? → Skip to step 7         │
│    Missing? → Continue               │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 3. Generate JWT                     │
│    - Header: {"typ":"JWT",          │
│              "alg":"RS256"}         │
│    - Payload: {"iat": now-60,       │
│               "exp": now+600,       │
│               "iss": CLIENT_ID}     │
│    - Sign with GITHUB_APP_PEM       │
│    Output: JWT (valid 10 min)       │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 4. Get Installation Access Token   │
│    POST: /app/installations/        │
│          {INSTALLATION_ID}/         │
│          access_tokens              │
│    Auth: Bearer {JWT}               │
│    Output: ACCESS_TOKEN (1 hour)    │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 5. Parse Organization URL           │
│    Input: https://github.com/Sysco  │
│    Extract: "Sysco"                 │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 6. Get Registration Token           │
│    POST: /orgs/{ORG}/actions/       │
│          runners/registration-token │
│    Auth: token {ACCESS_TOKEN}       │
│    Output: RUNNER_TOKEN (1 hour)    │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 7. Configure Runner                 │
│    ./config.sh                      │
│      --url {ORG_URL}                │
│      --token {REGISTRATION_TOKEN}   │
│      --name {RUNNER_NAME}           │
│      --labels your-runner-label     │
│      --unattended                   │
│    Creates: .runner file            │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 8. Start Runner Service             │
│    exec /home/runner/bin/runsvc.sh  │
└─────────────────────────────────────┘
```

### **Required Environment Variables**

| Variable | Description | Example |
|----------|-------------|---------|
| `GITHUB_APP_CLIENT_ID` | GitHub App Client ID | `123456` |
| `GITHUB_APP_PEM` | GitHub App Private Key (PEM format) | `-----BEGIN RSA PRIVATE KEY-----...` |
| `GITHUB_APP_INSTALLATION_ID` | Installation ID for your org | `12345678` |
| `RUNNER_ORGANIZATION_URL` | Full URL to organization | `https://github.com/your-organization` |
| `RUNNER_NAME` | Name for the runner | `aws-github-runner` |
| `RUNNER_WORK_DIRECTORY` | Working directory (optional) | `_work` (default) |
| `RUNNER_REPLACE_EXISTING` | Replace existing runner (optional) | `true` (default) |
| `RUNNER_LABELS` | Custom labels (optional) | `your-runner-label` |

### **Authentication Details**

**GitHub App Authentication (3-step process):**

#### **Step 1: JWT Generation**
```bash
# Create JWT with RS256 algorithm
Header:  {"typ":"JWT","alg":"RS256"}
Payload: {"iat":timestamp-60, "exp":timestamp+600, "iss":"CLIENT_ID"}
Signature: Sign with GITHUB_APP_PEM using SHA256

JWT Format: {base64url(header)}.{base64url(payload)}.{base64url(signature)}
Lifetime: 10 minutes
```

#### **Step 2: Installation Access Token**
```bash
POST /app/installations/{INSTALLATION_ID}/access_tokens
Authorization: Bearer {JWT}

Response:
{
  "token": "ghs_xxxxxxxxxxxx",
  "expires_at": "2024-01-01T13:00:00Z"
}

Lifetime: 1 hour
Scope: Limited to installation permissions
```

#### **Step 3: Runner Registration Token**
```bash
POST /orgs/{ORG_NAME}/actions/runners/registration-token
Authorization: token {INSTALLATION_ACCESS_TOKEN}

Response:
{
  "token": "ABCDEF...",
  "expires_at": "2024-01-01T13:00:00Z"
}

Lifetime: 1 hour
Usage: One-time registration
```

### **URL Parsing Logic**

The script extracts the organization name from the full URL:

```bash
Input:  RUNNER_ORGANIZATION_URL="https://github.com/your-organization"

Step 1: Extract protocol
        _PROTO="https://"

Step 2: Remove protocol
        _URL="github.com/your-organization"

Step 3: Extract organization name
        _PATH="your-organization"

Used in: https://api.github.com/orgs/your-organization/actions/runners/registration-token
```

### **Example Usage**

```bash
docker run -d \
  -e GITHUB_APP_CLIENT_ID="123456" \
  -e GITHUB_APP_PEM="-----BEGIN RSA PRIVATE KEY-----..." \
  -e GITHUB_APP_INSTALLATION_ID="12345678" \
  -e RUNNER_ORGANIZATION_URL="https://github.com/your-organization" \
  -e RUNNER_NAME="aws-github-runner-org" \
  github-runner:terraform
```

---

## 🔒 Security Considerations

### **Standalone Runners**
- ✅ PAT stored in AWS Parameter Store
- ✅ Scoped to specific repository
- ⚠️ PAT has broad permissions within scope
- 🔄 Rotate PAT annually

### **Organization Runners**
- ✅ GitHub App credentials in Parameter Store
- ✅ More granular permissions
- ✅ Installation-scoped tokens
- ✅ Short-lived tokens (JWT: 10min, Access: 1hr)
- 🔄 Rotate PEM key every 6-12 months

---

## 🔄 The `.runner` File

Both entrypoints check for a `.runner` file before registration:

```bash
if [[ -f ".runner" ]]; then
    echo "Runner already configured. Skipping config."
else
    # Perform full registration...
fi
```

### **Why This Matters**

**First Container Start:**
- No `.runner` file exists
- Full registration process executes
- `./config.sh` creates `.runner` file
- Runner registers with GitHub

**Container Restart (Same Task):**
- `.runner` file exists
- Skips registration
- Uses existing runner identity
- Faster startup (~5 seconds vs ~30 seconds)

**New Task/Container:**
- Fresh filesystem, no `.runner`
- Full registration executes
- `--replace` flag removes old runner
- New runner identity created

### **.runner File Contents**

```json
{
  "agentId": 123,
  "agentName": "aws-github-runner-org",
  "poolId": 1,
  "poolName": "Default",
  "serverUrl": "https://pipelines.actions.githubusercontent.com/...",
  "gitHubUrl": "https://github.com/your-organization",
  "workFolder": "_work"
}
```

---

## 📊 Comparison Table

| Feature | Standalone (`entrypoint.sh`) | Organization (`entrypoint-org.sh`) |
|---------|------------------------------|-------------------------------------|
| **Authentication** | PAT | GitHub App (Client ID + PEM) |
| **Scope** | Single repository | Entire organization |
| **Token Steps** | 1 step | 3 steps (JWT → Access → Registration) |
| **Token Lifetime** | PAT: No expiry | JWT: 10min, Access: 1hr |
| **Security** | Medium | High (scoped, short-lived) |
| **Setup Complexity** | Simple | Moderate |
| **Best For** | Testing, single repo | Production, multiple repos |
| **Permission Granularity** | Broad (entire repo) | Fine-grained (app permissions) |

---

## 🚀 Building the Image

```bash
# Build
docker build -t github-runner:terraform .

# Push to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  XXXXXXXXXXXX.dkr.ecr.us-east-1.amazonaws.com

docker tag github-runner:terraform \
  XXXXXXXXXXXX.dkr.ecr.us-east-1.amazonaws.com/github-runner:terraform

docker push \
  XXXXXXXXXXXX.dkr.ecr.us-east-1.amazonaws.com/github-runner:terraform
```

---

## 🐛 Troubleshooting

### **Common Issues**

#### **1. "Failed to get registration token"**
**Standalone:**
- Check PAT has correct scopes (`repo`, `workflow`)
- Verify PAT hasn't expired
- Confirm repository URL is correct

**Organization:**
- Verify GitHub App is installed on the organization
- Check Installation ID matches
- Ensure app has "Self-hosted runners" permissions

#### **2. "Runner already exists with that name"**
**Solution:**
- Set `RUNNER_REPLACE_EXISTING=true` (default)
- Or manually remove old runner from GitHub UI

#### **3. "JWT generation failed"**
**Organization only:**
- Verify PEM format is correct (includes headers/footers)
- Check for newline issues in PEM
- Ensure Client ID is correct

#### **4. Container restarts frequently**
**Check:**
- `.runner` file persistence
- Network connectivity
- GitHub API rate limits
- CloudWatch logs for errors

---

## 📝 Environment Variable Priority

Both entrypoints follow this priority:

1. **Explicit Environment Variable** (highest priority)
2. **Default Value** (if not set)
3. **Error Exit** (if required and missing)

### **Examples**

```bash
# RUNNER_NAME not set
→ Uses hostname as fallback

# GITHUB_ACCESS_TOKEN not set (standalone)
→ Error and exit

# RUNNER_REPLACE_EXISTING not set
→ Defaults to "true"
```

---

## 📚 Additional Resources

- [GitHub Actions Self-hosted Runner Docs](https://docs.github.com/en/actions/hosting-your-own-runners)
- [GitHub Apps Documentation](https://docs.github.com/en/developers/apps)
- [Runner Registration API](https://docs.github.com/en/rest/actions/self-hosted-runners)
- [JWT Authentication](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app)

---

## 🏗️ Architecture Integration

This Docker image is deployed via Terraform on AWS ECS Fargate. The entrypoint selection is controlled at deployment time:

```hcl
# Terraform automatically selects entrypoint based on runner_type
entryPoint = var.runner_type == "org" ? ["/entrypoint-org.sh"] : ["/entrypoint.sh"]
```

See `../terraform/` directory for infrastructure configuration.

---

**Version**: 1.0  
**Last Updated**: 2025-01-02  
**Maintained By**: SCM SRE Team

