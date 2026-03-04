#!/bin/bash
# User-data for Production Chatwoot ASG EC2 instances.
#
# AMI prerequisite: Docker already installed.
# Attached IAM Role: must allow ssm:GetParametersByPath on /chatwoot/production/*
#
# This script does NOT run db:chatwoot_prepare — the CI pipeline handles it
# via SSM (aws ssm send-command) before the rolling update.

set -euo pipefail

ENV="production"
REGION="eu-west-3"
CHATWOOT_DIR="/opt/chatwoot"
COMPOSE_FILE="$CHATWOOT_DIR/docker-compose.yml"
ENV_FILE="$CHATWOOT_DIR/.env"
LOG_FILE="/var/log/userdata.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== userdata-production.sh started at $(date) ==="

# ─────────────────────────────────────────────────────────────────────────────
# 1. Working directory
# ─────────────────────────────────────────────────────────────────────────────

mkdir -p "$CHATWOOT_DIR"
chmod 750 "$CHATWOOT_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# 2. Generate .env from SSM Parameter Store
#
# get-parameters-by-path fetches ALL parameters under /chatwoot/production/
# in a single API call (secrets decrypted with --with-decryption).
# Each line in the .env file = VARIABLE_NAME=value
# ─────────────────────────────────────────────────────────────────────────────

echo "Fetching SSM parameters from /chatwoot/${ENV}/ ..."

aws ssm get-parameters-by-path \
  --path "/chatwoot/${ENV}/" \
  --with-decryption \
  --recursive \
  --region "$REGION" \
  --query "Parameters[*].[Name,Value]" \
  --output text | while IFS=$'\t' read -r name value; do
    key=$(basename "$name")
    printf '%s=%s\n' "$key" "$value"
  done > "$ENV_FILE"

# Variables statiques (ne changent jamais, inutile de les mettre dans SSM)
cat >> "$ENV_FILE" <<'EOF'

# ── App ──────────────────────────────────────────────────────────────────────
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker
RAILS_LOG_TO_STDOUT=true

# ── PostgreSQL ────────────────────────────────────────────────────────────────
POSTGRES_PORT=5432
POSTGRES_USERNAME=chatwoot
POSTGRES_DATABASE=chatwoot_production

# ── Redis TLS (Elasticache) ────────────────────────────────────────────────
REDIS_OPENSSL_VERIFY_MODE=none

# ── Storage (S3) ─────────────────────────────────────────────────────────────
ACTIVE_STORAGE_SERVICE=amazon
AWS_REGION=eu-west-3
EOF

# Restrict read access to owner only (.env contains secrets)
chmod 600 "$ENV_FILE"
chown ubuntu:ubuntu "$ENV_FILE"
echo ".env generated ($( wc -l < "$ENV_FILE") lines)"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Fetch docker-compose from GitLab
# ─────────────────────────────────────────────────────────────────────────────

REGISTRY_TOKEN=$(aws ssm get-parameter \
  --name "/chatwoot/${ENV}/GITLAB_REGISTRY_TOKEN" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region "$REGION")

echo "Downloading docker-compose.production.yml ..."
curl -fsSL \
  --header "PRIVATE-TOKEN: ${REGISTRY_TOKEN}" \
  "https://gitlab.com/batch23-gr1/chatwoot/-/raw/main/docker-compose.production.yml" \
  -o "$COMPOSE_FILE"

chown ubuntu:ubuntu "$COMPOSE_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Login GitLab Container Registry + pull images
# ─────────────────────────────────────────────────────────────────────────────

echo "Login GitLab Container Registry ..."
echo "$REGISTRY_TOKEN" | docker login registry.gitlab.com \
  -u gitlab+deploy-token --password-stdin

echo "Pulling Docker images ..."
cd "$CHATWOOT_DIR"
docker compose pull rails sidekiq

# ─────────────────────────────────────────────────────────────────────────────
# 5. Start services
#    Do NOT run db:chatwoot_prepare here — the CI pipeline handles it
#    via SSM send-command before the ASG rolling update.
# ─────────────────────────────────────────────────────────────────────────────

echo "Starting Chatwoot (rails + sidekiq) ..."
docker compose up -d rails sidekiq

# ─────────────────────────────────────────────────────────────────────────────
# 6. Local health check (retry 20x, 15s delay = 5 minutes max)
# ─────────────────────────────────────────────────────────────────────────────

echo "Waiting for health check on localhost:3000/health ..."
for i in $(seq 1 20); do
  if curl -sf http://localhost:3000/health > /dev/null; then
    echo "Health check OK (attempt ${i}/20)"
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "ERROR: health check failed after 20 attempts" >&2
    exit 1
  fi
  echo "Attempt ${i}/20 — waiting 15s ..."
  sleep 15
done

# Clean up old images to free up disk space
docker image prune -f

echo "=== userdata-production.sh completed successfully at $(date) ==="
