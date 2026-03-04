#!/bin/bash
set -e


# Récupérer l'ID de l'instance via les metadata EC2, documentation : https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

# Lire le tag Environment de l'instance
SSM_ENV=$(aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=Environment" \
  --query "Tags[0].Value" \
  --output text \
  --region "eu-west-3")

# Récupérer le mot de passe Grafana depuis SSM
GRAFANA_PASSWORD=$(aws ssm get-parameter \
  --name "/chatwoot/$SSM_ENV/GRAFANA_PASSWORD" \
  --with-decryption \
  --region "eu-west-3" \
  --query "Parameter.Value" \
  --output text)

# Générer le .env
echo "GRAFANA_PASSWORD=${GRAFANA_PASSWORD}" > "/app/monitoring/.env"
chmod 600 "/app/monitoring/.env"

# Lancer les containers
cd "/app/monitoring"
docker compose -f docker-compose-monitoring.yml pull
docker compose -f docker-compose-monitoring.yml up -d
