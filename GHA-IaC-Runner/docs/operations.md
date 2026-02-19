# Operations Guide

Day-to-day operational reference for the platform CI infrastructure.

---

## Making Infrastructure Changes

All Terraform changes follow the same process:

```
1. Edit .tf files in terraform/
2. git commit
3. git push origin main
4. GitHub Actions runs terraform apply automatically
```

That's it. Do not run `terraform apply` locally.

---

## Checking CI Status

**GitHub Actions dashboard:**
Go to your repository → Actions → "Terraform Apply" workflow.

Each run shows:
- Which commit triggered it
- Duration of each step
- Full Terraform plan and apply output
- Pass/fail status

**Common failure modes:**

| Error in CI | Likely cause | Resolution |
|---|---|---|
| `Error: configuring Terraform AWS Provider` | OIDC token issue or role misconfigured | Check IAM role trust policy |
| `Error: acquiring the state lock` | Another apply is in progress | Wait for it to finish |
| `Error: state lock info` | Previous run crashed mid-apply | Follow lock removal procedure below |
| `Error: Invalid provider configuration` | `providers.tf` syntax error | Fix the HCL and push |
| `403 Forbidden` on S3 | IAM policy too restrictive | Add required S3 permissions to IAM policy |

---

## State Lock Management

Terraform acquires a lock in DynamoDB before running `apply`. The lock is released when the apply completes. If a CI job is interrupted mid-apply (e.g. runner timeout, network failure), the lock may remain.

**Check for active locks:**

```bash
aws dynamodb scan \
  --table-name "$(jq -r .dynamodb_table inventory.json)" \
  --region "$(jq -r .aws_region inventory.json)"
```

**Remove a stale lock (only if certain the apply is not in progress):**

```bash
# Get the LockID from the scan output above
aws dynamodb delete-item \
  --table-name "$(jq -r .dynamodb_table inventory.json)" \
  --region "$(jq -r .aws_region inventory.json)" \
  --key '{"LockID": {"S": "LOCK_ID_HERE"}}'
```

Alternatively, use Terraform's built-in force-unlock (requires local credentials):

```bash
cd terraform
terraform init \
  -backend-config="bucket=$(jq -r .s3_bucket ../../inventory.json)" \
  -backend-config="key=platform/terraform.tfstate" \
  -backend-config="region=$(jq -r .aws_region ../../inventory.json)" \
  -backend-config="dynamodb_table=$(jq -r .dynamodb_table ../../inventory.json)"

terraform force-unlock LOCK_ID
```

**Only force-unlock if you are certain no apply is actively running.** Force-unlocking during a live apply can corrupt state.

---

## Inspecting Terraform State

To view the current state without modifying it:

```bash
cd terraform

terraform init \
  -backend-config="bucket=$(jq -r .s3_bucket ../inventory.json)" \
  -backend-config="key=platform/terraform.tfstate" \
  -backend-config="region=$(jq -r .aws_region ../inventory.json)" \
  -backend-config="dynamodb_table=$(jq -r .dynamodb_table ../inventory.json)"

terraform show
terraform state list
```

This requires local AWS credentials with S3 read access.

---

## Recovering Previous State Versions

The S3 bucket has versioning enabled. If state is corrupted:

**List previous state versions:**

```bash
aws s3api list-object-versions \
  --bucket "$(jq -r .s3_bucket inventory.json)" \
  --prefix "platform/terraform.tfstate" \
  --region "$(jq -r .aws_region inventory.json)"
```

**Download a specific version:**

```bash
aws s3api get-object \
  --bucket "$(jq -r .s3_bucket inventory.json)" \
  --key "platform/terraform.tfstate" \
  --version-id "VERSION_ID_HERE" \
  terraform.tfstate.backup
```

**Restore by uploading the backup:**

```bash
aws s3 cp terraform.tfstate.backup \
  "s3://$(jq -r .s3_bucket inventory.json)/platform/terraform.tfstate" \
  --region "$(jq -r .aws_region inventory.json)"
```

---

## Adding Application Infrastructure

To manage application infrastructure through this CI pipeline:

1. Create a `modules/` directory under `terraform/`
2. Add module directories with your `.tf` files
3. Reference them from `terraform/providers.tf`:

```hcl
module "networking" {
  source = "./modules/networking"
  region = var.aws_region
}

module "database" {
  source     = "./modules/database"
  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids
}
```

4. Extend the IAM policy in `terraform/iam/main.tf` to grant Terraform the permissions your modules need.
5. Push to `main` — CI will apply the changes.

---

## Tearing Down the Platform

To destroy all platform CI infrastructure:

```bash
bash uninstall.sh
```

The uninstaller will:
1. Read `inventory.json`
2. Show exactly what will be destroyed
3. Require you to type `DESTROY` to confirm
4. Check for active state locks and refuse if one exists
5. Destroy IAM, S3, and DynamoDB in the correct order
6. Remove the workflow file
7. Delete `inventory.json`

This is irreversible. All Terraform state stored in S3 will be deleted.

---

## Cost Monitoring

Monthly costs for the platform infrastructure are typically under $1 USD:

| Resource | Pricing Model | Approximate Cost |
|---|---|---|
| S3 (state storage) | Per GB stored + requests | < $0.10/month |
| DynamoDB (lock table) | On-demand, per request | < $0.01/month |
| IAM + OIDC | Free | $0 |
| GitHub Actions runners | Per minute used | Depends on run frequency |

To track GitHub Actions usage: GitHub → Settings → Billing → Actions.

Free-tier GitHub accounts include 2,000 minutes/month on public repos and 500MB of storage.

---

## Routine Maintenance

**Quarterly:**
- Review IAM policy permissions — remove any that are no longer needed
- Check if Terraform version in the workflow should be updated
- Review S3 lifecycle policy — adjust retention if needed

**When GitHub rotates OIDC thumbprint:**
- GitHub will announce this in advance
- Update `thumbprint_list` in `terraform/iam/main.tf`
- Push to main — CI will update the OIDC provider

**When rotating to a new AWS account:**
- Run `uninstall.sh` in the old account
- Run `install.sh` with the new account's credentials
