#!/usr/bin/env bash
# =============================================================================
# install.sh — Terraform Platform CI Infrastructure Bootstrap
#
# Purpose  : One-time admin action to provision all platform CI infrastructure.
# Usage    : bash install.sh
# Rules    : No flags. Interactive only. Idempotent guard via inventory.json.
# =============================================================================

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

INVENTORY_FILE="inventory.json"
TF_BACKEND_DIR="terraform/backend"
TF_IAM_DIR="terraform/iam"
WORKFLOW_SRC=".github/workflows/terraform-apply.yaml"

# ─── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERR]${RESET}  $*" >&2; }
fatal()   { error "$*"; exit 1; }
divider() { echo -e "${BOLD}──────────────────────────────────────────────────${RESET}"; }

# ─── Pre-flight: Guard against re-install ─────────────────────────────────────
if [[ -f "$INVENTORY_FILE" ]]; then
  echo ""
  warn "inventory.json already exists — a previous install may have partially completed."
  echo ""
  echo "  Options:"
  echo "    [r] Retry  — re-run install using existing resource names (safe if resources exist)"
  echo "    [x] Abort  — exit without changes"
  echo ""
  read -rp "$(echo -e "${YELLOW}Choose [r/x]:${RESET} ")" RETRY_CHOICE
  case "$RETRY_CHOICE" in
    r|R)
      info "Retrying install with existing inventory..."
      # Load existing values so resource names stay consistent
      AWS_REGION_SAVED=$(jq -r '.aws_region'         "$INVENTORY_FILE" 2>/dev/null || true)
      S3_BUCKET_SAVED=$(jq -r '.s3_bucket'           "$INVENTORY_FILE" 2>/dev/null || true)
      DYNAMODB_SAVED=$(jq -r '.dynamodb_table'        "$INVENTORY_FILE" 2>/dev/null || true)
      IAM_ROLE_SAVED=$(jq -r '.iam_role_name'         "$INVENTORY_FILE" 2>/dev/null || true)
      GITHUB_ORG_SAVED=$(jq -r '.github_org'          "$INVENTORY_FILE" 2>/dev/null || true)
      GITHUB_REPO_SAVED=$(jq -r '.github_repo'        "$INVENTORY_FILE" 2>/dev/null || true)
      DEFAULT_BRANCH_SAVED=$(jq -r '.default_branch'  "$INVENTORY_FILE" 2>/dev/null || true)
      TF_WATCH_DIR_SAVED=$(jq -r '.tf_watch_dir'       "$INVENTORY_FILE" 2>/dev/null || true)
      rm -f "$INVENTORY_FILE"
      ;;
    *)
      fatal "Aborted. Run uninstall.sh first to start clean, or choose [r] to retry."
      ;;
  esac
fi

# ─── Pre-flight: Must be inside a Git repo ────────────────────────────────────
if ! git rev-parse --git-dir &>/dev/null; then
  fatal "Not inside a Git repository. Clone or init this repo first."
fi

# ─── Pre-flight: Required tools ───────────────────────────────────────────────
for cmd in aws terraform git jq; do
  if ! command -v "$cmd" &>/dev/null; then
    fatal "Required tool not found: $cmd. Please install it and re-run."
  fi
done

divider
echo -e "${BOLD}  Terraform Platform CI Bootstrap${RESET}"
divider
echo ""
info "This script will provision:"
echo "    • S3 bucket       — Terraform remote state"
echo "    • DynamoDB table  — State locking"
echo "    • IAM OIDC role   — GitHub Actions authentication"
echo "    • GitHub Actions workflow"
echo ""

# ─── Prompt: AWS Region ───────────────────────────────────────────────────────
if [[ -n "${AWS_REGION_SAVED:-}" ]]; then
  AWS_REGION="$AWS_REGION_SAVED"
  info "Using saved AWS region: $AWS_REGION"
else
  read -rp "$(echo -e "${BOLD}Enter AWS region${RESET} [us-east-1]: ")" AWS_REGION
  AWS_REGION="${AWS_REGION:-us-east-1}"
fi

# ─── Prompt: Terraform watch directory ───────────────────────────────────────
if [[ -n "${TF_WATCH_DIR_SAVED:-}" ]]; then
  TF_WATCH_DIR="$TF_WATCH_DIR_SAVED"
  info "Using saved Terraform watch directory: $TF_WATCH_DIR"
else
  read -rp "$(echo -e "${BOLD}Enter Terraform directory to watch${RESET} (required, e.g. terraform): ")" TF_WATCH_DIR
  # No default — an empty value means the workflow would trigger on every push.
  # Force the user to be explicit about what Terraform is watching.
  if [[ -z "${TF_WATCH_DIR// }" ]]; then
    fatal "Terraform watch directory is required. Re-run install.sh and provide a directory name (e.g. terraform)."
  fi
  # Strip leading/trailing slashes for consistency
  TF_WATCH_DIR="${TF_WATCH_DIR#/}"
  TF_WATCH_DIR="${TF_WATCH_DIR%/}"
fi

# Create the directory if it doesn't exist
if [[ ! -d "$TF_WATCH_DIR" ]]; then
  info "Directory '$TF_WATCH_DIR' not found — creating it..."
  mkdir -p "$TF_WATCH_DIR"
  success "Created directory: $TF_WATCH_DIR"
else
  success "Terraform watch directory exists: $TF_WATCH_DIR"
fi

# ─── Ensure providers.tf exists in watch directory ────────────────────────────
# This is critical for the pipeline to use the S3 backend properly.
# Without this file, Terraform falls back to local state even when -backend-config
# flags are passed, causing orphaned resources.
if [[ ! -f "$TF_WATCH_DIR/providers.tf" ]]; then
  info "Creating providers.tf in $TF_WATCH_DIR..."
  cat > "$TF_WATCH_DIR/providers.tf" << 'PROVIDERS_EOF'
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "REPLACE_WITH_REGION"
}
PROVIDERS_EOF

  # Replace the placeholder with actual region
  sed -i "s/REPLACE_WITH_REGION/$AWS_REGION/g" "$TF_WATCH_DIR/providers.tf"
  success "Created $TF_WATCH_DIR/providers.tf with backend configuration"
else
  success "providers.tf already exists in $TF_WATCH_DIR"
fi

# ─── Verify AWS auth ──────────────────────────────────────────────────────────
info "Verifying AWS credentials..." 
CALLER_IDENTITY=$(aws sts get-caller-identity --region "$AWS_REGION" 2>&1) \
  || fatal "AWS authentication failed. Configure credentials (SSO, env vars, or ~/.aws/credentials) and retry.\n\n$CALLER_IDENTITY"

AWS_ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
AWS_CALLER_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
success "Authenticated as: $AWS_CALLER_ARN (account: $AWS_ACCOUNT_ID)"

# ─── Detect Git context ───────────────────────────────────────────────────────
REMOTE_URL=$(git remote get-url origin 2>/dev/null) \
  || fatal "No Git remote 'origin' found. Add one: git remote add origin <url>"

# Parse GitHub org and repo from HTTPS or SSH remotes
if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  GITHUB_ORG="${BASH_REMATCH[1]}"
  GITHUB_REPO="${BASH_REMATCH[2]}"
else
  fatal "Could not parse GitHub org/repo from remote URL: $REMOTE_URL\nExpected format: git@github.com:org/repo.git or https://github.com/org/repo.git"
fi

DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||') \
  || DEFAULT_BRANCH="main"

success "GitHub context: $GITHUB_ORG/$GITHUB_REPO (branch: $DEFAULT_BRANCH)"

# ─── Generate unique resource names (or restore from retry) ───────────────────
if [[ -n "${S3_BUCKET_SAVED:-}" ]]; then
  S3_BUCKET="$S3_BUCKET_SAVED"
  DYNAMODB_TABLE="$DYNAMODB_SAVED"
  IAM_ROLE_NAME="$IAM_ROLE_SAVED"
  GITHUB_ORG="$GITHUB_ORG_SAVED"
  GITHUB_REPO="$GITHUB_REPO_SAVED"
  DEFAULT_BRANCH="$DEFAULT_BRANCH_SAVED"
  info "Using saved resource names from previous install attempt."
else
  SUFFIX=$(echo "${GITHUB_ORG}-${GITHUB_REPO}-${AWS_ACCOUNT_ID}" \
    | sha256sum | head -c 8)

  S3_BUCKET="tf-state-${GITHUB_REPO:0:20}-${SUFFIX}"
  S3_BUCKET=$(echo "$S3_BUCKET" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | cut -c1-63)

  DYNAMODB_TABLE="tf-lock-${GITHUB_REPO:0:20}-${SUFFIX}"
  DYNAMODB_TABLE=$(echo "$DYNAMODB_TABLE" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

  IAM_ROLE_NAME="github-actions-terraform-${GITHUB_REPO:0:30}"
  IAM_ROLE_NAME=$(echo "$IAM_ROLE_NAME" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ─── Resource creation plan ───────────────────────────────────────────────────
echo ""
divider
echo -e "${BOLD}  Resources to be created:${RESET}"
divider
printf "  %-22s %s\n" "AWS Region:"       "$AWS_REGION"
printf "  %-22s %s\n" "S3 Bucket:"        "$S3_BUCKET"
printf "  %-22s %s\n" "DynamoDB Table:"   "$DYNAMODB_TABLE"
printf "  %-22s %s\n" "IAM Role:"         "$IAM_ROLE_NAME"
printf "  %-22s %s\n" "GitHub Repo:"      "$GITHUB_ORG/$GITHUB_REPO"
printf "  %-22s %s\n" "TF Watch Dir:"     "$TF_WATCH_DIR"
printf "  %-22s %s\n" "Workflow file:"    "$WORKFLOW_SRC"
echo ""

read -rp "$(echo -e "${YELLOW}Proceed? (yes/no):${RESET} ")" CONFIRM
[[ "$CONFIRM" == "yes" ]] || fatal "Aborted by user."

# ─── Write inventory.json ─────────────────────────────────────────────────────
info "Writing inventory.json..."
cat > "$INVENTORY_FILE" <<EOF
{
  "aws_region":       "$AWS_REGION",
  "aws_account_id":   "$AWS_ACCOUNT_ID",
  "s3_bucket":        "$S3_BUCKET",
  "dynamodb_table":   "$DYNAMODB_TABLE",
  "iam_role_name":    "$IAM_ROLE_NAME",
  "github_org":       "$GITHUB_ORG",
  "github_repo":      "$GITHUB_REPO",
  "default_branch":   "$DEFAULT_BRANCH",
  "tf_watch_dir":     "$TF_WATCH_DIR",
  "created_at":       "$TIMESTAMP"
}
EOF
success "inventory.json written."

# ─── Provision backend (S3 + DynamoDB) via Terraform ─────────────────────────
info "Provisioning Terraform backend (S3 + DynamoDB)..."

pushd "$TF_BACKEND_DIR" > /dev/null

terraform init -upgrade -reconfigure \
  -backend=false \
  2>&1 | sed 's/^/    /'

# Import existing resources if they already exist (idempotent re-run safety)
if aws s3api head-bucket --bucket "$S3_BUCKET" --region "$AWS_REGION" &>/dev/null; then
  warn "S3 bucket $S3_BUCKET already exists — importing into Terraform state."
  terraform import \
    -var "aws_region=$AWS_REGION" \
    -var "s3_bucket_name=$S3_BUCKET" \
    -var "dynamodb_table_name=$DYNAMODB_TABLE" \
    aws_s3_bucket.state "$S3_BUCKET" \
    2>&1 | sed 's/^/    /' || true
fi

if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &>/dev/null; then
  warn "DynamoDB table $DYNAMODB_TABLE already exists — importing into Terraform state."
  terraform import \
    -var "aws_region=$AWS_REGION" \
    -var "s3_bucket_name=$S3_BUCKET" \
    -var "dynamodb_table_name=$DYNAMODB_TABLE" \
    aws_dynamodb_table.lock "$DYNAMODB_TABLE" \
    2>&1 | sed 's/^/    /' || true
fi

terraform apply -auto-approve \
  -var "aws_region=$AWS_REGION" \
  -var "s3_bucket_name=$S3_BUCKET" \
  -var "dynamodb_table_name=$DYNAMODB_TABLE" \
  2>&1 | sed 's/^/    /'

popd > /dev/null
success "S3 bucket and DynamoDB table provisioned."

# ─── Provision IAM OIDC role via Terraform ────────────────────────────────────
info "Provisioning IAM OIDC role for GitHub Actions..."

pushd "$TF_IAM_DIR" > /dev/null

terraform init -upgrade -reconfigure \
  -backend=false \
  2>&1 | sed 's/^/    /'

# Import existing OIDC provider if it already exists (idempotent re-run safety)
OIDC_ARN=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
  --output text 2>/dev/null || true)

if [[ -n "$OIDC_ARN" && "$OIDC_ARN" != "None" ]]; then
  warn "GitHub OIDC provider already exists ($OIDC_ARN) — importing into Terraform state."
  terraform import \
    -var "aws_region=$AWS_REGION" \
    -var "iam_role_name=$IAM_ROLE_NAME" \
    -var "github_org=$GITHUB_ORG" \
    -var "github_repo=$GITHUB_REPO" \
    -var "aws_account_id=$AWS_ACCOUNT_ID" \
    -var "s3_bucket_name=$S3_BUCKET" \
    -var "dynamodb_table_name=$DYNAMODB_TABLE" \
    aws_iam_openid_connect_provider.github "$OIDC_ARN" \
    2>&1 | sed 's/^/    /' || true
fi

# Import existing IAM role if it already exists (policy attachment is recreated by apply)
if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
  warn "IAM role $IAM_ROLE_NAME already exists — importing into Terraform state."
  terraform import \
    -var "aws_region=$AWS_REGION" \
    -var "iam_role_name=$IAM_ROLE_NAME" \
    -var "github_org=$GITHUB_ORG" \
    -var "github_repo=$GITHUB_REPO" \
    -var "aws_account_id=$AWS_ACCOUNT_ID" \
    -var "s3_bucket_name=$S3_BUCKET" \
    -var "dynamodb_table_name=$DYNAMODB_TABLE" \
    aws_iam_role.github_actions "$IAM_ROLE_NAME" \
    2>&1 | sed 's/^/    /' || true
fi

terraform apply -auto-approve \
  -var "aws_region=$AWS_REGION" \
  -var "iam_role_name=$IAM_ROLE_NAME" \
  -var "github_org=$GITHUB_ORG" \
  -var "github_repo=$GITHUB_REPO" \
  -var "aws_account_id=$AWS_ACCOUNT_ID" \
  -var "s3_bucket_name=$S3_BUCKET" \
  -var "dynamodb_table_name=$DYNAMODB_TABLE" \
  2>&1 | sed 's/^/    /'

IAM_ROLE_ARN=$(terraform output -raw iam_role_arn)

popd > /dev/null
success "IAM OIDC role provisioned: $IAM_ROLE_ARN"

# ─── Update inventory.json with role ARN ─────────────────────────────────────
jq --arg arn "$IAM_ROLE_ARN" '. + {iam_role_arn: $arn}' "$INVENTORY_FILE" > "${INVENTORY_FILE}.tmp" \
  && mv "${INVENTORY_FILE}.tmp" "$INVENTORY_FILE"
success "inventory.json updated with IAM role ARN."

# ─── Install GitHub Actions workflow ─────────────────────────────────────────
info "Installing GitHub Actions workflow..."
mkdir -p .github/workflows

cat > "$WORKFLOW_SRC" <<WORKFLOW
name: Terraform Apply

on:
  push:
    branches:
      - ${DEFAULT_BRANCH}
    paths:
      - '${TF_WATCH_DIR}/**/*.tf'
      - '${TF_WATCH_DIR}/**/*.tfvars'

permissions:
  id-token: write   # Required for GitHub OIDC token
  contents: read

jobs:
  terraform:
    name: Terraform Apply
    runs-on: ubuntu-latest
    environment: production

    env:
      AWS_REGION: ${AWS_REGION}
      TF_BUCKET: ${S3_BUCKET}
      TF_LOCK_TABLE: ${DYNAMODB_TABLE}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Debug OIDC token claims
        run: |
          TOKEN=\$(curl -sSfL -H "Authorization: bearer \$ACTIONS_ID_TOKEN_REQUEST_TOKEN" \\
            "\$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r '.value')
          echo "=== OIDC sub claim (must match IAM trust policy) ==="
          echo "\$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.sub'

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${IAM_ROLE_ARN}
          aws-region: \${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~> 1.7"

      - name: Terraform Init
        working-directory: ${TF_WATCH_DIR}
        run: |
          terraform init \\
            -backend-config="bucket=\${{ env.TF_BUCKET }}" \\
            -backend-config="key=platform/terraform.tfstate" \\
            -backend-config="region=\${{ env.AWS_REGION }}" \\
            -backend-config="dynamodb_table=\${{ env.TF_LOCK_TABLE }}" \\
            -backend-config="encrypt=true"

      - name: Terraform Validate
        working-directory: ${TF_WATCH_DIR}
        run: terraform validate

      - name: Terraform Plan
        working-directory: ${TF_WATCH_DIR}
        run: terraform plan -out=tfplan

      - name: Terraform Apply
        working-directory: ${TF_WATCH_DIR}
        run: terraform apply -auto-approve tfplan
WORKFLOW

success "GitHub Actions workflow written to $WORKFLOW_SRC"

# ─── Success summary ──────────────────────────────────────────────────────────
echo ""
divider
echo -e "${GREEN}${BOLD}  Bootstrap Complete!${RESET}"
divider
echo ""
echo -e "  ${BOLD}Resources created:${RESET}"
printf "  ✓  %-22s %s\n" "S3 bucket:"      "$S3_BUCKET"
printf "  ✓  %-22s %s\n" "DynamoDB table:" "$DYNAMODB_TABLE"
printf "  ✓  %-22s %s\n" "IAM role:"       "$IAM_ROLE_ARN"
printf "  ✓  %-22s %s\n" "Workflow:"       "$WORKFLOW_SRC"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo "    1. Commit and push this repository to GitHub"
echo "    2. GitHub Actions will trigger on push to '$DEFAULT_BRANCH'"
echo "    3. Terraform will run in CI — never locally"
  echo "    4. Only changes to '$TF_WATCH_DIR/**/*.tf' trigger the workflow"
  echo "    5. To destroy application infra: bash destroy.sh"
echo ""
echo -e "  ${YELLOW}Keep inventory.json committed. It is the platform source of truth.${RESET}"
echo ""
