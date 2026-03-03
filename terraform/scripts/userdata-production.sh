#!/bin/bash

# Le script s'arrête si command fail/variable non définie
set -euo pipefail

# Setup d'un dossier de travail
mkdir -p /app/chatwoot
cd /app/chatwoot

# Copy le docker-compose depuis le repo public (curl déjà dans l'AMI custom)
curl -sL "https://gitlab.com/batch23-gr1/chatwoot/-/raw/main/docker-compose.production.yaml" \
  -o /app/chatwoot/docker-compose.yml

# Get le .env depuis SSM (aws-cli déjà dans l'AMI custom)
aws ssm get-parameter \
  --name "/chatwoot/prod/.env" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region "eu-west-3" > /app/chatwoot/.env

# Login Gitlab Registry (si privé, si public enlever cette partie)
REGISTRY_TOKEN=$(aws ssm get-parameter \
  --name "/chatwoot/registry-token" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region "eu-west-3")
echo "$REGISTRY_TOKEN" | docker login registry.gitlab.com -u gitlab+deploy-token-12554657 --password-stdin

# Pull les images et lancer Chatwoot
docker compose pull
docker compose up -d
docker image prune -f  # Clean les anciennes images au fur et à mesure