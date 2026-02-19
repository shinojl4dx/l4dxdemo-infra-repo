#!/usr/bin/env bash
# =============================================================================
# uninstall.sh — Terraform Platform CI Infrastructure Teardown
#
# Purpose  : Fully reverse everything created by install.sh.
# Usage    : bash uninstall.sh
# Rules    : No flags. No guessing. Requires explicit DESTROY confirmation.
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
WORKFLOW_FILE=".github/workflows/terraform-apply.yaml"

# ─── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERR]${RESET}  $*" >&2; }
fatal()   { error "$*"; exit 1; }
divider() { echo -e "${BOLD}──────────────────────────────────────────────────${RESET}"; }

# ─── Pre-flight: inventory.json must exist ────────────────────────────────────
if [[ ! -f "$INVENTORY_FILE" ]]; then
  fatal "inventory.json not found. Nothing to uninstall.\nRun install.sh first to bootstrap the platform."
fi

# ─── Pre-flight: Required tools ───────────────────────────────────────────────
for cmd in aws terraform jq; do
  if ! command -v "$cmd" &>/dev/null; then
    fatal "Required tool not found: $cmd. Please install it and re-run."
  fi
done

# ─── Load inventory ───────────────────────────────────────────────────────────
AWS_REGION=$(jq -r '.aws_region'       "$INVENTORY_FILE")
S3_BUCKET=$(jq -r '.s3_bucket'         "$INVENTORY_FILE")
DYNAMODB_TABLE=$(jq -r '.dynamodb_table' "$INVENTORY_FILE")
IAM_ROLE_NAME=$(jq -r '.iam_role_name' "$INVENTORY_FILE")
IAM_ROLE_ARN=$(jq -r '.iam_role_arn // "unknown"' "$INVENTORY_FILE")
GITHUB_ORG=$(jq -r '.github_org'       "$INVENTORY_FILE")
GITHUB_REPO=$(jq -r '.github_repo'     "$INVENTORY_FILE")
CREATED_AT=$(jq -r '.created_at'       "$INVENTORY_FILE")

# ─── Check for active Terraform state lock ────────────────────────────────────
info "Checking for active DynamoDB state locks..."
LOCK_COUNT=$(aws dynamodb scan \
  --table-name "$DYNAMODB_TABLE" \
  --region "$AWS_REGION" \
  --select "COUNT" \
  --query 'Count' \
  --output text 2>/dev/null) || LOCK_COUNT=0

if [[ "$LOCK_COUNT" -gt 0 ]]; then
  fatal "Terraform state is currently LOCKED ($LOCK_COUNT lock(s) in $DYNAMODB_TABLE).\nRefusing to destroy while a plan or apply is in progress.\nWait for CI to finish or manually remove the lock before uninstalling."
fi
success "No active state locks found."

# ─── Destruction plan ─────────────────────────────────────────────────────────
echo ""
divider
echo -e "${RED}${BOLD}  ⚠  DESTRUCTION PLAN  ⚠${RESET}"
divider
echo ""
echo -e "  The following resources will be ${RED}PERMANENTLY DESTROYED${RESET}:"
echo ""
printf "  ✗  %-22s %s\n" "S3 bucket:"          "$S3_BUCKET"
printf "  ✗  %-22s %s\n" "DynamoDB table:"     "$DYNAMODB_TABLE"
printf "  ✗  %-22s %s\n" "IAM role:"           "$IAM_ROLE_ARN"
printf "  ✗  %-22s %s\n" "Workflow file:"      "$WORKFLOW_FILE"
printf "  ✗  %-22s %s\n" "Inventory file:"     "$INVENTORY_FILE"
echo ""
printf "  %-22s %s\n" "Installed:"          "$CREATED_AT"
printf "  %-22s %s/%s\n" "GitHub repo:"     "$GITHUB_ORG" "$GITHUB_REPO"
printf "  %-22s %s\n" "AWS Region:"         "$AWS_REGION"
echo ""
warn  "All Terraform state stored in S3 will be DELETED. This cannot be undone."
echo ""

# ─── Require explicit confirmation ────────────────────────────────────────────
read -rp "$(echo -e "${RED}${BOLD}Type DESTROY to continue (anything else aborts):${RESET} ")" CONFIRM
[[ "$CONFIRM" == "DESTROY" ]] || fatal "Aborted. No resources were modified."

echo ""
info "Proceeding with teardown..."
echo ""

# ─── Destroy IAM role ─────────────────────────────────────────────────────────
info "Destroying IAM OIDC role..."
if [[ -d "$TF_IAM_DIR" ]]; then
  pushd "$TF_IAM_DIR" > /dev/null

  terraform init -upgrade -reconfigure \
    -backend=false \
    2>&1 | sed 's/^/    /'

  terraform destroy -auto-approve \
    -var "aws_region=$AWS_REGION" \
    -var "iam_role_name=$IAM_ROLE_NAME" \
    -var "github_org=$GITHUB_ORG" \
    -var "github_repo=$GITHUB_REPO" \
    -var "aws_account_id=$(jq -r '.aws_account_id' "../../$INVENTORY_FILE")" \
    2>&1 | sed 's/^/    /'

  popd > /dev/null
  success "IAM role destroyed."
else
  warn "terraform/iam directory not found — skipping IAM destroy."
fi

# ─── Destroy S3 bucket ────────────────────────────────────────────────────────
info "Emptying and destroying S3 bucket: $S3_BUCKET..."

# Must empty versioned bucket before deletion
aws s3api delete-objects \
  --bucket "$S3_BUCKET" \
  --region "$AWS_REGION" \
  --delete "$(aws s3api list-object-versions \
    --bucket "$S3_BUCKET" \
    --region "$AWS_REGION" \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json 2>/dev/null || echo '{"Objects":[]}')" \
  > /dev/null 2>&1 || true

aws s3api delete-objects \
  --bucket "$S3_BUCKET" \
  --region "$AWS_REGION" \
  --delete "$(aws s3api list-object-versions \
    --bucket "$S3_BUCKET" \
    --region "$AWS_REGION" \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json 2>/dev/null || echo '{"Objects":[]}')" \
  > /dev/null 2>&1 || true

# Now destroy via Terraform
if [[ -d "$TF_BACKEND_DIR" ]]; then
  pushd "$TF_BACKEND_DIR" > /dev/null

  terraform init -upgrade -reconfigure \
    -backend=false \
    2>&1 | sed 's/^/    /'

  terraform destroy -auto-approve \
    -var "aws_region=$AWS_REGION" \
    -var "s3_bucket_name=$S3_BUCKET" \
    -var "dynamodb_table_name=$DYNAMODB_TABLE" \
    2>&1 | sed 's/^/    /'

  popd > /dev/null
  success "S3 bucket and DynamoDB table destroyed."
else
  warn "terraform/backend directory not found — attempting direct deletion."
  aws s3 rb "s3://$S3_BUCKET" --force --region "$AWS_REGION" 2>/dev/null && \
    success "S3 bucket deleted." || warn "S3 bucket may not exist."
  aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" 2>/dev/null && \
    success "DynamoDB table deleted." || warn "DynamoDB table may not exist."
fi

# ─── Remove workflow file ─────────────────────────────────────────────────────
if [[ -f "$WORKFLOW_FILE" ]]; then
  rm -f "$WORKFLOW_FILE"
  success "Workflow file removed: $WORKFLOW_FILE"
else
  warn "Workflow file not found — already removed."
fi

# ─── Delete inventory.json ────────────────────────────────────────────────────
rm -f "$INVENTORY_FILE"
success "inventory.json deleted."

# ─── Completion summary ───────────────────────────────────────────────────────
echo ""
divider
echo -e "${GREEN}${BOLD}  Teardown Complete!${RESET}"
divider
echo ""
echo "  All platform CI infrastructure has been destroyed:"
echo "    ✓  S3 state bucket deleted"
echo "    ✓  DynamoDB lock table deleted"
echo "    ✓  IAM OIDC role deleted"
echo "    ✓  GitHub Actions workflow removed"
echo "    ✓  inventory.json deleted"
echo ""
echo "  The repository is clean. Run install.sh to start over."
echo ""
