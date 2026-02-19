# Bootstrap Guide

This guide covers the one-time process of initialising the platform CI infrastructure. After bootstrap, all Terraform is managed exclusively by GitHub Actions.

---

## Prerequisites

Before running `install.sh`, ensure the following are in place:

**Local tools:**

| Tool | Minimum Version | Install |
|---|---|---|
| `aws` CLI | v2.x | [docs.aws.amazon.com](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| `terraform` | 1.7.0+ | [developer.hashicorp.com](https://developer.hashicorp.com/terraform/install) |
| `git` | Any | OS package manager |
| `jq` | 1.6+ | OS package manager |

**AWS access:**

You need temporary AWS administrator credentials. The recommended approach is AWS SSO:

```bash
aws sso login --profile your-admin-profile
export AWS_PROFILE=your-admin-profile
```

Alternatively, export credentials directly:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...   # if using temporary credentials
```

Verify credentials work:

```bash
aws sts get-caller-identity
```

**GitHub repository:**

- This repository must have a remote named `origin` pointing to GitHub
- The remote URL must be parseable as `github.com/{org}/{repo}`
- Example: `git@github.com:my-org/my-platform.git`

---

## Running the Installer

```bash
bash install.sh
```

The installer is interactive and will:

1. Verify Git repository context
2. Verify required tools are installed
3. Verify AWS credentials
4. Detect GitHub org, repo, and default branch
5. Prompt you to confirm the AWS region
6. Show you all resources it will create
7. Ask for explicit confirmation before creating anything
8. Provision S3, DynamoDB, and IAM via Terraform
9. Write `inventory.json`
10. Install the GitHub Actions workflow
11. Print a success summary

**The installer runs for approximately 2–4 minutes.**

---

## Expected Installer Output

```
──────────────────────────────────────────────────
  Terraform Platform CI Bootstrap
──────────────────────────────────────────────────

[INFO] This script will provision:
    • S3 bucket       — Terraform remote state
    • DynamoDB table  — State locking
    • IAM OIDC role   — GitHub Actions authentication
    • GitHub Actions workflow

Enter AWS region [us-east-1]:

[INFO] Verifying AWS credentials...
[OK]   Authenticated as: arn:aws:iam::123456789012:user/admin (account: 123456789012)

──────────────────────────────────────────────────
  Resources to be created:
──────────────────────────────────────────────────
  AWS Region:            us-east-1
  S3 Bucket:             tf-state-myrepo-a1b2c3d4
  DynamoDB Table:        tf-lock-myrepo-a1b2c3d4
  IAM Role:              github-actions-terraform-myrepo
  GitHub Repo:           my-org/myrepo
  Workflow file:         .github/workflows/terraform-apply.yaml

Proceed? (yes/no): yes

[INFO] Writing inventory.json...
[OK]   inventory.json written.
[INFO] Provisioning Terraform backend (S3 + DynamoDB)...
    ... terraform output ...
[OK]   S3 bucket and DynamoDB table provisioned.
[INFO] Provisioning IAM OIDC role for GitHub Actions...
    ... terraform output ...
[OK]   IAM role provisioned.
[OK]   GitHub Actions workflow written.

──────────────────────────────────────────────────
  Bootstrap Complete!
──────────────────────────────────────────────────

  Resources created:
  ✓  S3 bucket:             tf-state-myrepo-a1b2c3d4
  ✓  DynamoDB table:        tf-lock-myrepo-a1b2c3d4
  ✓  IAM role:              arn:aws:iam::123456789012:role/github-actions-terraform-myrepo
  ✓  Workflow:              .github/workflows/terraform-apply.yaml

  Next steps:
    1. Commit and push this repository to GitHub
    2. GitHub Actions will trigger on push to 'main'
    3. Terraform will run in CI — never locally
```

---

## Post-Install Steps

After the installer succeeds:

**1. Commit everything to Git:**

```bash
git add inventory.json .github/workflows/terraform-apply.yaml
git commit -m "chore: bootstrap platform CI infrastructure"
git push origin main
```

**2. Verify GitHub Actions triggered:**

Go to your repository on GitHub → Actions tab. You should see a workflow run named "Terraform Apply" in progress.

**3. Verify the run succeeded:**

The run will `init`, `validate`, `plan`, and `apply`. Since `terraform/providers.tf` contains no resources yet, the plan should show "No changes."

**4. Discard your admin AWS credentials:**

From this point forward, no one needs local AWS credentials. CI handles everything.

---

## Idempotency

The installer is guarded by `inventory.json`. If you run `install.sh` again while `inventory.json` exists, it will exit immediately with an error:

```
[ERR]  inventory.json already exists. Platform is already bootstrapped.
       Run uninstall.sh first if you need to start over.
```

This prevents accidental double-provisioning.

---

## Troubleshooting

**"Not inside a Git repository"**
: Ensure you cloned this repo and are running the script from within it.

**"Required tool not found: jq"**
: Install `jq` using your OS package manager (`brew install jq`, `apt install jq`, etc.).

**"AWS authentication failed"**
: Run `aws sts get-caller-identity` manually to debug. Ensure credentials are exported or configured in `~/.aws`.

**"Could not parse GitHub org/repo from remote URL"**
: Run `git remote get-url origin` and verify it matches `git@github.com:org/repo.git` or `https://github.com/org/repo.git`.

**Terraform errors during provisioning**
: The installer prints all Terraform output. Read the error message — it usually identifies the specific resource and reason. Common causes: S3 bucket name already taken globally (the hash should prevent this), IAM permissions insufficient.
