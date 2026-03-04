# Chatwoot Infrastructure

Terraform infrastructure for Chatwoot (Rails) on AWS — `eu-west-3` (Paris).

## Environments

| Environment | Architecture |
| --- | --- |
| `staging` | 1 public subnet · Bastion + App EC2 + Monitoring EC2 |
| `production` | 2 AZs · ALB · ASG · RDS PostgreSQL 16 · Elasticache Redis 7 · S3 |

## Repository Structure

```text
terraform/
├── bootstrap/                  # One-time setup: S3 bucket + DynamoDB table
├── environments/
│   ├── staging/                # main.tf · variables.tf · terraform.tfvars · outputs.tf
│   └── production/             # main.tf · variables.tf · terraform.tfvars · outputs.tf
├── modules/
│   └── networking/             # Shared VPC module (used by both environments)
└── scripts/
    └── userdata-production.sh  # EC2 boot script: pulls .env from SSM, starts Docker
```

Only one shared module exists (`networking`). Everything environment-specific is inlined directly in the environment's `main.tf`.

---

## Remote State: S3 + DynamoDB Locking

Terraform state is stored remotely in S3. Concurrent applies are prevented by a DynamoDB lock.

### How it works

```text
terraform apply
  │
  ├── 1. DynamoDB  →  PutItem LockID (conditional write)
  │        ├── attribute_not_exists → lock acquired ✅
  │        └── key already exists  → STOP: "state is locked" ❌
  │
  ├── 2. S3        →  download terraform.tfstate
  │
  ├── 3.           →  compute plan (diff state vs real AWS)
  │
  ├── 4.           →  apply changes on AWS
  │
  ├── 5. S3        →  upload new terraform.tfstate
  │
  └── 6. DynamoDB  →  DeleteItem LockID (release lock)
```

The DynamoDB table is **empty at rest**. A record present means a lock is held.
The conditional write (`attribute_not_exists`) is atomic — no race condition possible.

Each environment locks independently (the lock key is the S3 path of the state file),
so a staging apply never blocks a production apply.

### Resources

| Resource | Purpose |
| --- | --- |
| S3 bucket `chatwoot-terraform-state` | Stores `.tfstate` files for all environments |
| DynamoDB table `chatwoot-terraform-locks` | Holds the lock during an active apply |

### If a lock is stuck (interrupted apply)

```bash
terraform force-unlock <LOCK_ID>
```

Or manually via AWS CLI:

```bash
aws dynamodb delete-item \
  --table-name chatwoot-terraform-locks \
  --key '{"LockID": {"S": "chatwoot-terraform-state/environments/production/terraform.tfstate"}}' \
  --region eu-west-3
```

---

## First-Time Setup

Bootstrap must run **before** any environment, as it creates the S3 bucket used as backend.

```bash
# 1. Create the S3 bucket and DynamoDB table (local state)
cd terraform/bootstrap
terraform init
terraform apply

# 2. Initialize environments (now the S3 backend exists)
cd ../environments/staging
terraform init
terraform apply

cd ../environments/production
terraform init
terraform apply
```

---

## SSM Parameter Store

Secrets and computed endpoints are stored under `/chatwoot/{env}/{VARIABLE_NAME}`.

`SecureString` parameters are created with a `PLACEHOLDER` value by Terraform and
never overwritten on subsequent applies (`lifecycle { ignore_changes = [value] }`).
Set real values once after the first apply:

```bash
aws ssm put-parameter \
  --name "/chatwoot/production/SECRET_KEY_BASE" \
  --value "$(openssl rand -hex 64)" \
  --type "SecureString" --overwrite --region eu-west-3
```

`String` parameters (RDS endpoint, Redis URL, S3 bucket name, frontend URL) are
populated automatically by Terraform on every apply.

At boot, each EC2 instance fetches all parameters in a single API call:

```bash
aws ssm get-parameters-by-path \
  --path "/chatwoot/production/" \
  --with-decryption \
  --region eu-west-3 \
  --query "Parameters[*].[Name,Value]" \
  --output text | while IFS=$'\t' read -r name value; do
    printf '%s=%s\n' "$(basename "$name")" "$value"
  done > /opt/chatwoot/.env
```
