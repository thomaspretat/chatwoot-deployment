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
│   ├── networking/             # Shared VPC module (used by both environments)
│   └── iam/                    # Shared IAM module (user CI/CD + EC2 role + instance profile)
└── scripts/
    └── userdata-production.sh  # EC2 boot script: pulls .env from SSM, starts Docker
```

Two shared modules exist: `networking` (VPC) and `iam` (users + EC2 role). Everything environment-specific is inlined directly in the environment's `main.tf`.

---

## IAM

### Module `modules/iam`

Créé et appelé par chaque environnement. Gère trois responsabilités :

| Ressource | Nom | Rôle |
| --- | --- | --- |
| `aws_iam_user` | `chatwoot-{env}` | User programmatique pour Terraform local et CI/CD GitLab |
| `aws_iam_access_key` | — | Clé d'accès associée au user |
| `aws_iam_role` | `chatwoot-{env}-ec2-role` | Rôle assumé par les instances EC2 au démarrage |
| `aws_iam_instance_profile` | `chatwoot-{env}-ec2-profile` | Attaché au Launch Template / `aws_instance` |

Le user reçoit la policy `AdministratorAccess` (droits Terraform complets sur le compte AWS).

Le rôle EC2 reçoit :

- `AmazonSSMReadOnlyAccess` — lecture des paramètres SSM au boot (les deux envs)
- Policy inline S3 R/W sur le bucket Chatwoot — production uniquement (`s3_bucket_arn` non vide)

### Récupérer les credentials après le premier apply

```bash
# Access Key ID (non sensible)
terraform output iam_access_key_id

# Secret Access Key (sensible — affiché en clair une seule fois)
terraform output -raw iam_secret_access_key
```

Configurer ensuite dans AWS CLI :

```bash
aws configure --profile chatwoot-production
# AWS Access Key ID: <iam_access_key_id>
# AWS Secret Access Key: <iam_secret_access_key>
# Default region: eu-west-3
```

Et dans les variables CI/CD GitLab du repo infra :

```text
AWS_ACCESS_KEY_ID     = <iam_access_key_id>
AWS_SECRET_ACCESS_KEY = <iam_secret_access_key>
AWS_DEFAULT_REGION    = eu-west-3
```

> **Note :** le Secret Access Key est stocké dans le state Terraform (S3 chiffré).
> Il n'est **pas** re-affichable via AWS Console après création — seul le state en garde la trace.

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

## Backup Policy

### RDS PostgreSQL

| Parameter | Value |
| --- | --- |
| Automated backups retention | **14 days** (PITR enabled) |
| Backup window | `03:00–04:00` UTC |
| Final snapshot on destroy | enabled (`chatwoot-{env}-final`) |
| Deletion protection | enabled |

AWS takes a daily snapshot and keeps the last 14. Point-in-Time Recovery (PITR) allows restoring to any second within that window.

### ElastiCache Redis

| Parameter | Value |
| --- | --- |
| Snapshot retention | **7 days** |
| Snapshot window | `04:00–05:00` UTC (after RDS window) |

Redis holds sessions, Sidekiq queues, and application cache — not the source of truth. PostgreSQL is the critical data store; Redis snapshots cover operational recovery only.

> **Long-term archiving:** for compliance or recovery windows beyond 14 days, export RDS snapshots to S3 via AWS Backup (max native retention is 35 days).

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
