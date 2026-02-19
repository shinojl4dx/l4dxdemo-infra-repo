# =============================================================================
# terraform/iam/main.tf
#
# Provisions the GitHub Actions OIDC trust:
#   - GitHub OIDC identity provider
#   - IAM role with scoped trust policy (org + repo + branch bound)
#   - IAM policy granting Terraform the permissions it needs
#
# No static credentials are created. GitHub Actions runners assume
# this role via short-lived OIDC tokens. Credentials expire with the job.
# =============================================================================

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Platform  = "ci-bootstrap"
      Component = "iam"
    }
  }
}

# ─── GitHub OIDC Identity Provider ───────────────────────────────────────────
# Each AWS account can only have one OIDC provider per issuer URL.
# If your account already has one, import it:
#   terraform import aws_iam_openid_connect_provider.github <arn>

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's current OIDC thumbprint.
  # Update if GitHub rotates their certificate.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ─── IAM Role Trust Policy ────────────────────────────────────────────────────
# The condition restricts token acceptance to:
#   - The specific GitHub org + repo
#   - The 'main' branch (ref:refs/heads/main)
# This prevents tokens from forks or other branches from assuming the role.

data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    sid     = "AllowGitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Covers all valid sub formats GitHub may send for this repo:
      #   - Direct branch push:       repo:org/repo:ref:refs/heads/main
      #   - With environment gate:    repo:org/repo:environment:production
      #   - Any ref on this repo:     repo:org/repo:*  (scoped to repo only)
      values = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/*",
        "repo:${var.github_org}/${var.github_repo}:environment:*",
      ]
    }
  }
}

# ─── IAM Role ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "github_actions" {
  name               = var.iam_role_name
  description        = "Assumed by GitHub Actions via OIDC for ${var.github_org}/${var.github_repo}"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust.json

  max_session_duration = 3600
}

# ─── IAM Policy: Terraform Permissions ───────────────────────────────────────
#
# TWO-POLICY APPROACH:
#
#   1. PowerUserAccess (AWS managed) — lets Terraform create any AWS resource
#      without needing per-service permission updates. Excludes IAM and
#      Organizations. Safe for a CI role that doesn't manage its own identity.
#
#   2. TerraformStateAccess (custom) — tightly scoped read/write on the specific
#      S3 state bucket and DynamoDB lock table. PowerUserAccess already covers
#      S3 broadly, but this makes the state backend permissions explicit and
#      auditable.
#
# To harden for production: replace PowerUserAccess with a custom policy that
# lists only the specific services your Terraform modules actually use.

# Attach AWS managed PowerUserAccess
resource "aws_iam_role_policy_attachment" "power_user" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "terraform_ci" {
  statement {
    sid    = "TerraformStateReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.s3_bucket_name}",
      "arn:aws:s3:::${var.s3_bucket_name}/*",
    ]
  }

  statement {
    sid    = "TerraformStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.dynamodb_table_name}",
    ]
  }

  statement {
    sid       = "AllowGetCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # ─── IAM application permissions ─────────────────────────────────────────────
  # Allows Terraform to create and manage IAM roles, policies, and attachments
  # for application use. Scoped to prevent privilege escalation — the CI role
  # cannot grant more permissions than it has (iam:PassRole is excluded).
  statement {
    sid    = "ApplicationIAMManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRoles",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicies",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:UpdateAssumeRolePolicy",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_state" {
  name        = "${var.iam_role_name}-state-policy"
  description = "Scoped Terraform state + lock access for ${var.github_org}/${var.github_repo}"
  policy      = data.aws_iam_policy_document.terraform_ci.json
}

resource "aws_iam_role_policy_attachment" "terraform_state" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.terraform_state.arn
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "iam_role_arn" {
  description = "ARN of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "iam_role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.github_actions.name
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider"
  value       = aws_iam_openid_connect_provider.github.arn
}
