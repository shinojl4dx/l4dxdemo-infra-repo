# Security Model

This document describes how authentication, authorisation, and secret management work across the platform.

---

## Authentication Layers

There are two distinct authentication contexts in this platform. They are intentionally separate and use completely different mechanisms.

### 1. Bootstrap (Admin, One-Time)

Used exclusively when running `install.sh` or `uninstall.sh`.

**Who:** A human platform engineer with AWS administrator access.

**How:** Standard AWS credentials — AWS SSO, environment variables, or `~/.aws/credentials`. These are short-lived and exist only on the engineer's machine for the duration of the bootstrap.

**What they can do:** Create and destroy the platform infrastructure (S3, DynamoDB, IAM). This is intentionally broad — bootstrapping requires admin access.

**After bootstrap:** These credentials are discarded. No admin credentials are stored anywhere.

### 2. CI Execution (GitHub Actions, Every Run)

Used every time GitHub Actions runs Terraform.

**Who:** The GitHub Actions runner — an ephemeral, GitHub-hosted VM.

**How:** GitHub Actions OIDC. The runner requests a short-lived token from GitHub's OIDC endpoint, then exchanges it for AWS temporary credentials via `sts:AssumeRoleWithWebIdentity`. The credentials are valid for 1 hour (the maximum GitHub Actions job duration) and then expire automatically.

**What they can do:** Read and write Terraform state in S3, acquire and release DynamoDB locks, and whatever additional permissions are explicitly added to the IAM policy for application infrastructure.

---

## GitHub Actions OIDC: How It Works

OpenID Connect (OIDC) allows GitHub Actions to authenticate to AWS without storing any secrets. The flow works as follows:

```
1. GitHub Actions job starts
        │
        ▼
2. Runner requests OIDC token from GitHub
   (token includes: repo, branch, job context)
        │
        ▼
3. Runner calls AWS STS AssumeRoleWithWebIdentity
   with the OIDC token
        │
        ▼
4. AWS validates token signature against GitHub's
   OIDC public keys
        │
        ▼
5. AWS checks IAM role trust policy conditions:
   - audience == "sts.amazonaws.com" ✓
   - sub == "repo:{org}/{repo}:ref:refs/heads/main" ✓
        │
        ▼
6. AWS returns temporary credentials
   (AccessKeyId, SecretAccessKey, SessionToken)
   Valid for 1 hour. Cannot be renewed.
        │
        ▼
7. Terraform uses credentials to read/write state
        │
        ▼
8. Job finishes. Credentials expire. Runner destroyed.
```

No secrets are stored. No credentials are rotated. No IAM users are created.

---

## IAM Role Trust Policy

The IAM role's trust policy is the critical security boundary. It restricts which GitHub Actions tokens can assume the role.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

**The `sub` condition** binds the role to:
- A specific GitHub org (`my-org`)
- A specific repository (`my-repo`)
- A specific branch (`refs/heads/main`)

A token from a fork, a different repo, or a feature branch **cannot** assume this role. This prevents supply chain attacks where a malicious PR could trigger CI and gain AWS access.

---

## IAM Policy (Principle of Least Privilege)

The IAM policy attached to the role grants only what Terraform needs for CI:

| Permission | Resource | Purpose |
|---|---|---|
| `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` | State bucket | Read and write Terraform state |
| `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem`, `dynamodb:DescribeTable` | Lock table | Acquire and release state locks |
| `sts:GetCallerIdentity` | `*` | Debugging and plan output |

For application infrastructure, add statements to `terraform/iam/main.tf` granting only the specific AWS actions your Terraform modules require.

---

## No Secrets Policy

This platform has no secrets to manage:

| Credential Type | Status | Reason |
|---|---|---|
| AWS access keys | ❌ None | OIDC eliminates the need |
| IAM user credentials | ❌ None | IAM roles only |
| GitHub Actions secrets | ❌ None | Role ARN is in the workflow file |
| Terraform state encryption key | ✅ AES256 | Managed by AWS SSE — no key material to store |
| Any `.env` files | ❌ None | Not applicable |

The workflow file contains the IAM role ARN in plain text. This is intentional and safe — the ARN is not a secret. The security comes from the IAM trust policy conditions, not from keeping the ARN hidden.

---

## Threat Model

| Threat | Mitigation |
|---|---|
| Attacker gains GitHub account access | Branch protection + required reviews prevent unauthorized pushes to `main` |
| Malicious pull request triggers CI | Trust policy is scoped to `refs/heads/main` — PR jobs cannot assume the role |
| Compromised runner exfiltrates credentials | Credentials expire in 1 hour; runner is ephemeral and destroyed after each job |
| State file tampered externally | S3 bucket is private; access requires the IAM role |
| Concurrent applies corrupt state | DynamoDB locking prevents concurrent applies |
| State contains sensitive resource attributes | S3 SSE encrypts all objects at rest |
| Bootstrap admin credentials compromised | Bootstrap is a one-time action; credentials should be discarded immediately after |

---

## Recommended GitHub Repository Settings

For maximum security, configure the following in GitHub:

**Branch protection on `main`:**
- Require pull request reviews before merging
- Require status checks to pass before merging
- Restrict who can push to `main`

**Environments:**
- Create a `production` GitHub Environment
- Add required reviewers for the environment
- This adds a manual approval gate before Terraform applies

These settings are outside the scope of this installer but are strongly recommended for production use.
