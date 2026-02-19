#!/usr/bin/env bash
# =============================================================================
# destroy.sh — Destroy Application Infrastructure
#
# Purpose  : Tears down all Terraform-managed application resources.
# Usage    : bash destroy.sh
# Scope    : Only destroys resources in the Terraform watch directory.
#            Does NOT touch platform infrastructure (S3 state, IAM role, etc).
# Rules    : Requires typing DESTROY to confirm. No flags. No guessing.
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
PROVIDERS_BORROWED=false

# ─── Helpers ──────────────────────────────────────────────────────────────────
info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error() { echo -e "${RED}[ERR]${RESET}  $*" >&2; }
fatal() {
    error "$*"
    exit 1
}
divider() { echo -e "${BOLD}──────────────────────────────────────────────────${RESET}"; }

cleanup() {
    if [[ "$PROVIDERS_BORROWED" == "true" && -f "$TF_WATCH_DIR/providers.tf" ]]; then
        info "Cleaning up borrowed providers.tf..."
        rm -f "$TF_WATCH_DIR/providers.tf"
        success "Removed temporary providers.tf"
    fi
}

trap cleanup EXIT

# ─── Pre-flight: inventory.json must exist ────────────────────────────────────
if [[ ! -f "$INVENTORY_FILE" ]]; then
    fatal "inventory.json not found. Run install.sh first to bootstrap the platform."
fi

# ─── Pre-flight: Required tools ───────────────────────────────────────────────
for cmd in terraform jq aws; do
    if ! command -v "$cmd" &>/dev/null; then
        fatal "Required tool not found: $cmd. Please install it and re-run."
    fi
done

# ─── Load inventory ───────────────────────────────────────────────────────────
AWS_REGION=$(jq -r '.aws_region' "$INVENTORY_FILE")
S3_BUCKET=$(jq -r '.s3_bucket' "$INVENTORY_FILE")
DYNAMODB_TABLE=$(jq -r '.dynamodb_table' "$INVENTORY_FILE")
TF_WATCH_DIR=$(jq -r '.tf_watch_dir' "$INVENTORY_FILE")
GITHUB_ORG=$(jq -r '.github_org' "$INVENTORY_FILE")
GITHUB_REPO=$(jq -r '.github_repo' "$INVENTORY_FILE")
CREATED_AT=$(jq -r '.created_at' "$INVENTORY_FILE")

# ─── Verify Terraform directory exists ────────────────────────────────────────
if [[ ! -d "$TF_WATCH_DIR" ]]; then
    fatal "Terraform directory not found: $TF_WATCH_DIR\nCheck inventory.json or create the directory."
fi

# ─── Ensure providers.tf exists in watch directory ────────────────────────────
if [[ ! -f "$TF_WATCH_DIR/providers.tf" ]]; then
    if [[ -f "terraform/providers.tf" ]]; then
        info "providers.tf not found in $TF_WATCH_DIR — borrowing from terraform/"
        cp terraform/providers.tf "$TF_WATCH_DIR/providers.tf"
        PROVIDERS_BORROWED=true
        success "Temporarily copied providers.tf (will be removed after destroy)"
    else
        fatal "No providers.tf found in $TF_WATCH_DIR or terraform/\nCannot connect to remote state backend without it."
    fi
fi

# ─── Check for active Terraform state lock with auto-removal ──────────────────
info "Checking for active DynamoDB state locks..."
LOCK_COUNT=$(aws dynamodb scan \
    --table-name "$DYNAMODB_TABLE" \
    --region "$AWS_REGION" \
    --select "COUNT" \
    --query 'Count' \
    --output text 2>/dev/null) || LOCK_COUNT=0

if [[ "$LOCK_COUNT" -gt 0 ]]; then
    warn "Found $LOCK_COUNT active state lock(s) in $DYNAMODB_TABLE"

    # Get lock details with safe extraction
    LOCK_INFO=$(aws dynamodb scan \
        --table-name "$DYNAMODB_TABLE" \
        --region "$AWS_REGION" \
        2>/dev/null || echo '{}')

    LOCK_ID=$(echo "$LOCK_INFO" | jq -r '.Items[0].LockID.S // "unknown"' 2>/dev/null)

    echo ""
    warn "Lock details:"
    printf "  %-20s %s\n" "Lock ID:" "$LOCK_ID"
    echo ""

    warn "This lock may be stale if:"
    echo "  - The GitHub Actions workflow already completed"
    echo "  - The pipeline crashed mid-apply"
    echo "  - No terraform operations are currently running"
    echo ""

    read -rp "$(echo -e "${YELLOW}Remove this lock? [y/N]:${RESET} ")" REMOVE_LOCK

    if [[ "${REMOVE_LOCK,,}" == "y" ]]; then
        info "Removing stale lock..."
        aws dynamodb delete-item \
            --table-name "$DYNAMODB_TABLE" \
            --region "$AWS_REGION" \
            --key '{"LockID": {"S": "'"$LOCK_ID"'"}}' \
            2>&1 | sed 's/^/    /'

        success "Lock removed. Continuing with destroy..."
    else
        fatal "Aborted. Wait for any running operations to finish, or manually remove the lock."
    fi
else
    success "No active state locks found."
fi

# ─── Initialize Terraform ─────────────────────────────────────────────────────
info "Initializing Terraform in $TF_WATCH_DIR..."
pushd "$TF_WATCH_DIR" >/dev/null

terraform init -upgrade \
    -backend-config="bucket=$S3_BUCKET" \
    -backend-config="key=platform/terraform.tfstate" \
    -backend-config="region=$AWS_REGION" \
    -backend-config="dynamodb_table=$DYNAMODB_TABLE" \
    -backend-config="encrypt=true" \
    2>&1 | sed 's/^/    /'

success "Terraform initialized."

# ─── Show destruction plan ────────────────────────────────────────────────────
info "Generating destroy plan..."
terraform plan -destroy -out=tfplan.destroy 2>&1 | sed 's/^/    /'

echo ""
divider
echo -e "${RED}${BOLD}  ⚠  DESTRUCTION PLAN  ⚠${RESET}"
divider
echo ""
warn "The resources shown above will be PERMANENTLY DESTROYED."
echo ""
printf "  %-22s %s\n" "Terraform directory:" "$TF_WATCH_DIR"
printf "  %-22s %s\n" "State backend:" "$S3_BUCKET"
printf "  %-22s %s\n" "AWS Region:" "$AWS_REGION"
printf "  %-22s %s/%s\n" "GitHub repo:" "$GITHUB_ORG" "$GITHUB_REPO"
echo ""
warn "This does NOT destroy platform infrastructure (S3 state, IAM role, DynamoDB)."
echo "  Use uninstall.sh to tear down the platform."
echo ""

# ─── Require explicit confirmation ────────────────────────────────────────────
read -rp "$(echo -e "${RED}${BOLD}Type DESTROY to continue (anything else aborts):${RESET} ")" CONFIRM
if [[ "$CONFIRM" != "DESTROY" ]]; then
    rm -f tfplan.destroy
    popd >/dev/null
    fatal "Aborted. No resources were modified."
fi

# ─── Execute destroy ──────────────────────────────────────────────────────────
echo ""
info "Executing destroy..."
terraform apply -auto-approve tfplan.destroy 2>&1 | sed 's/^/    /'

rm -f tfplan.destroy
popd >/dev/null

# ─── Success summary ──────────────────────────────────────────────────────────
echo ""
divider
echo -e "${GREEN}${BOLD}  Destroy Complete!${RESET}"
divider
echo ""
echo "  All application infrastructure in '$TF_WATCH_DIR' has been destroyed."
echo ""
echo "  Platform infrastructure remains intact:"
echo "    ✓  S3 state bucket ($S3_BUCKET)"
echo "    ✓  DynamoDB lock table ($DYNAMODB_TABLE)"
echo "    ✓  IAM OIDC role"
echo ""
echo "  To tear down the platform itself, run: bash uninstall.sh"
echo ""
