#!/bin/bash
set -e

# Récupérer l'ID de l'instance via les metadata EC2, documentation : https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

# Lire le tag Environment de l'instance (production ou staging)
SSM_ENV=$(aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=Environment" \
  --query "Tags[0].Value" \
  --output text \
  --region "eu-west-3")

# Mapper le tag vers le nom du compose file
if [ "$SSM_ENV" = "production" ]; then
  COMPOSE_FILE="docker-compose-prod.yml"
else
  COMPOSE_FILE="docker-compose-staging.yml"
fi

# Récupérer tous les paramètres SSM du path /chatwoot/{env}/ (--recursive pour paginer automatiquement au-delà de 10 résultats)
PARAMETERS=$(aws ssm get-parameters-by-path \
  --path "/chatwoot/$SSM_ENV/" \
  --recursive \
  --with-decryption \
  --region "eu-west-3" \
  --query "Parameters[*].[Name,Value]" \
  --output text)

# Générer le .env, on pipe le résultat SSM dans une boucle qui transforme chaque ligne en VAR=valeur
echo "$PARAMETERS" | while IFS=$'\t' read -r name value; do   # sépare entre le path et la valeur via un tab avec IFS=$'\t'
  echo "$(basename "$name")=$value"                           # récupere le nom uniquement et pas le path, exemple: /home/fichier.txt → fichier.txt
done > /app/chatwoot/.env

chmod 600 /app/chatwoot/.env

# Se connecter au registry privé GitLab
source /app/chatwoot/.env
echo "$GITLAB_REGISTRY_TOKEN" | docker login registry.gitlab.com -u gitlab+deploy-token-12554657 --password-stdin

# Lancer les containers
cd "/app/chatwoot"
docker compose -f "$COMPOSE_FILE" pull

# Initialiser/migrer la DB avant de lancer notre compose
docker compose -f "$COMPOSE_FILE" run --rm -T rails bundle exec rails db:chatwoot_prepare || true # si une autre instance fait déjà la migration, on continue
docker compose -f "$COMPOSE_FILE" up -d

