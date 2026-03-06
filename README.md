# Chatwoot Infrastructure

Terraform + Packer + Ansible infrastructure for Chatwoot (Rails) on AWS — `eu-west-3` (Paris).

## Environments

| Environment | Architecture |
| --- | --- |
| `staging` | 1 AZ · 1 public subnet · Bastion + App EC2 (DB in Docker) + Monitoring EC2 |
| `production` | 2 AZs · ALB · ASG · Bastion · Monitoring EC2 · RDS PostgreSQL 16 · ElastiCache Redis 7 · S3 |

## Repository Structure

```text
infra/
├── packer/
│   ├── common.pkr.hcl             # Plugins + Ubuntu 24.04 data source (shared)
│   ├── bastion.pkr.hcl            # AMI bastion (SSH hardening only)
│   ├── chatwoot.pkr.hcl           # AMI app (Docker + compose + start script)
│   └── monitoring.pkr.hcl         # AMI monitoring (Docker + Prometheus/Grafana)
│
├── ansible/
│   ├── bastion-playbook.yml       # fail2ban, UFW, SSH port 2022
│   ├── chatwoot-playbook.yml      # Docker, AWS CLI, compose files, systemd service
│   └── monitoring-playbook.yml    # Docker, AWS CLI, compose + prometheus configs, systemd service
│
├── docker/
│   ├── docker-compose-prod.yml    # Rails + Sidekiq + node-exporter + redis-exporter
│   ├── docker-compose-staging.yml # Rails + Sidekiq + Postgres + Redis + nginx + node-exporter + redis-exporter
│   ├── docker-compose-monitoring.yml  # Prometheus + Grafana + node-exporter
│   ├── config/
│   │   ├── prometheus-prod.yml    # Scrape config filtered by Environment=production
│   │   ├── prometheus-staging.yml # Scrape config filtered by Environment=staging
│   │   └── nginx.conf             # Reverse proxy for staging (port 80 → Rails 3000)
│   └── scripts/
│       ├── chatwoot-start.sh      # Boot script: detect env, fetch SSM → .env, docker compose up
│       └── monitoring-start.sh    # Boot script: fetch Grafana password, select prometheus config, docker compose up
│
└── terraform/
    ├── bootstrap/                 # One-time setup: S3 bucket + DynamoDB table for remote state
    ├── environments/
    │   ├── staging/               # main.tf · variables.tf · terraform.tfvars · outputs.tf
    │   └── production/            # main.tf · variables.tf · terraform.tfvars · outputs.tf
    └── modules/
        ├── networking/            # VPC, subnets, IGW, NAT GW, route tables
        └── iam/                   # IAM user (CI/CD) + EC2 role (SSM + S3) + instance profile
```

Two shared Terraform modules: `networking` (VPC) and `iam` (users + EC2 role). Everything environment-specific is inlined in the environment's `main.tf`.

---

## Packer / Ansible — AMI Build

Packer builds 3 AMIs from Ubuntu 24.04, provisioned by Ansible :

| AMI | Packer file | Ansible playbook | Installs |
| --- | --- | --- | --- |
| `bastion-{timestamp}` | `bastion.pkr.hcl` | `bastion-playbook.yml` | fail2ban, UFW, SSH hardening (port 2022) |
| `chatwoot-{timestamp}` | `chatwoot.pkr.hcl` | `chatwoot-playbook.yml` | Docker, AWS CLI, compose files, systemd service, pre-pulled images |
| `monitoring-{timestamp}` | `monitoring.pkr.hcl` | `monitoring-playbook.yml` | Docker, AWS CLI, compose + prometheus configs, systemd service |

Each AMI is shared between prod and staging. The differentiation happens at boot via EC2 tags.

Terraform uses `data "aws_ami"` to automatically fetch the latest AMI by name prefix — no hardcoded AMI IDs.

```bash
# Build an AMI
cd infra/packer
packer init .
packer build bastion.pkr.hcl
```

---

## Monitoring — Prometheus + Grafana

### Architecture

The monitoring instance runs 3 containers :

- **Prometheus** (`:9090`) — scrapes metrics every 15s and stores them as time-series
- **Grafana** (`:3000`) — dashboards, connects to Prometheus as data source
- **node-exporter** (`:9100`) — exposes host metrics (CPU, RAM, disk) of the monitoring instance itself

### What gets scraped

On each app instance (prod and staging), two exporters run alongside the application :

- **node-exporter** (`:9100`) — host metrics (CPU, RAM, disk, network)
- **redis-exporter** (`:9121`) — Redis/ElastiCache metrics (connections, memory, commands/s)

Prometheus discovers app instances automatically via **EC2 service discovery** (`ec2_sd_configs`). It calls the AWS API `DescribeInstances`, filters by tags (`Role=chatwoot` + `Environment=production|staging`), and scrapes their private IPs. No hardcoded IPs — new ASG instances are discovered automatically.

Two separate Prometheus configs exist (`prometheus-prod.yml` / `prometheus-staging.yml`) to ensure each monitoring instance only scrapes its own environment. The correct config is selected at boot by `monitoring-start.sh`.

### Access

Monitoring is in a private subnet (prod). Access Grafana via SSH tunnel through the bastion :

```bash
ssh -J ubuntu@<bastion_ip>:2022 -L 3000:<monitoring_private_ip>:3000 ubuntu@<monitoring_private_ip> -p 2022
# Then open http://localhost:3000
```

---

## IAM

### Module `modules/iam`

| Resource | Name | Purpose |
| --- | --- | --- |
| `aws_iam_user` | `chatwoot-{env}` | Programmatic user for Terraform and CI/CD |
| `aws_iam_role` | `chatwoot-{env}-ec2-role` | Role assumed by EC2 instances at boot |
| `aws_iam_instance_profile` | `chatwoot-{env}-ec2-profile` | Attached to Launch Template / `aws_instance` |

The EC2 role has :

- `AmazonSSMReadOnlyAccess` — read SSM parameters at boot
- `ec2:DescribeTags` — detect environment from instance tags
- S3 R/W policy on the Chatwoot bucket — production only

### Retrieve credentials after first apply

```bash
terraform output iam_access_key_id
terraform output -raw iam_secret_access_key
```

---

## Deployment Flow

Terraform never runs for app deployments. Two repos, two responsibilities.

### Repo `chatwoot` (app) — deploy a new version

Steps 1–2 are common, then it diverges per environment.

```text
merge → staging (or main for prod)
  │
  ├── 1. docker build → registry.gitlab.com/org/chatwoot:$CI_COMMIT_SHORT_SHA
  └── 2. docker push
```

**Production** (ASG + Instance Refresh) :

```text
  ├── 3. aws ssm put-parameter --name /chatwoot/production/DOCKER_IMAGE_TAG --value <tag> --overwrite
  └── 4. aws autoscaling start-instance-refresh --auto-scaling-group-name chatwoot-production-asg
         → AWS replaces instances one by one (zero-downtime)
         → each new instance boots, reads SSM → docker pull → up
```

**Staging** (single EC2 + SSM Run Command) :

```text
  ├── 3. aws ssm put-parameter --name /chatwoot/staging/DOCKER_IMAGE_TAG --value <tag> --overwrite
  └── 4. aws ssm send-command --instance-ids <app_instance_id> --document-name "AWS-RunShellScript"
         → re-generates .env from SSM, pulls new image, restarts rails + sidekiq
```

### Repo `chatwoot-infra` (infra) — modify infrastructure

```text
merge → main
  ├── 1. terraform fmt + validate
  ├── 2. terraform plan
  ├── 3. [manual approval for production]
  └── 4. terraform apply
```

### Rollback

```bash
aws ssm put-parameter \
  --name "/chatwoot/production/DOCKER_IMAGE_TAG" \
  --value "registry.gitlab.com/org/chatwoot:<old-tag>" \
  --overwrite --region eu-west-3

aws autoscaling start-instance-refresh \
  --auto-scaling-group-name chatwoot-production-asg \
  --region eu-west-3
```

---

## SSM Parameter Store

Secrets and computed endpoints are stored under `/chatwoot/{env}/{VARIABLE_NAME}`.

`SecureString` parameters are created with a `PLACEHOLDER` value by Terraform and never overwritten on subsequent applies (`lifecycle { ignore_changes = [value] }`). Set real values once after first apply :

```bash
aws ssm put-parameter \
  --name "/chatwoot/production/SECRET_KEY_BASE" \
  --value "$(openssl rand -hex 64)" \
  --type "SecureString" --overwrite --region eu-west-3
```

`String` parameters (RDS endpoint, Redis URL, S3 bucket name, etc.) are populated automatically by Terraform.

At boot, each EC2 instance fetches all parameters in a single API call via `chatwoot-start.sh` :

```bash
aws ssm get-parameters-by-path \
  --path "/chatwoot/$SSM_ENV/" \
  --with-decryption --region eu-west-3 \
  --query "Parameters[*].[Name,Value]" --output text \
  | while IFS=$'\t' read -r name value; do
      echo "$(basename "$name")=$value"
    done > /app/chatwoot/.env
```

---

## Remote State: S3 + DynamoDB Locking

Terraform state is stored in S3. Concurrent applies are prevented by a DynamoDB lock.

| Resource | Purpose |
| --- | --- |
| S3 bucket `chatwoot-terraform-state` | Stores `.tfstate` files for all environments |
| DynamoDB table `chatwoot-terraform-locks` | Holds the lock during an active apply |

Each environment locks independently (the lock key is the S3 path), so staging never blocks production.

```bash
# If a lock is stuck (interrupted apply)
terraform force-unlock <LOCK_ID>
```

---

## First-Time Setup

Bootstrap must run **before** any environment.

```bash
# 1. Create S3 bucket + DynamoDB table (local state)
cd infra/terraform/bootstrap
terraform init && terraform apply

# 2. Build AMIs
cd ../../packer
packer init .
packer build bastion.pkr.hcl
packer build chatwoot.pkr.hcl
packer build monitoring.pkr.hcl

# 3. Initialize environments
cd ../terraform/environments/staging
terraform init && terraform apply

cd ../production
terraform init && terraform apply

# 4. Set secrets in SSM (once per env)
aws ssm put-parameter --name "/chatwoot/production/SECRET_KEY_BASE" \
  --value "$(openssl rand -hex 64)" --type SecureString --overwrite --region eu-west-3
# ... repeat for POSTGRES_PASSWORD, REDIS_PASSWORD, SMTP_PASSWORD, GRAFANA_PASSWORD, GITLAB_REGISTRY_TOKEN
```

---

## Backup Policy

### RDS PostgreSQL

| Parameter | Value |
| --- | --- |
| Automated backups retention | **14 days** (PITR enabled) |
| Backup window | `03:00–04:00` UTC |
| Final snapshot on destroy | enabled |
| Deletion protection | enabled |

### ElastiCache Redis

| Parameter | Value |
| --- | --- |
| Snapshot retention | **5 days** |
| Maintenance window | `05:00–06:00` UTC |

Redis holds sessions, Sidekiq queues, and cache — not the source of truth. PostgreSQL is the critical data store.
