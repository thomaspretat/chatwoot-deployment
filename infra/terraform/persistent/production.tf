# SSM Parameter Store — Production
# Valeurs par défaut "TO_FILL" : à remplir via AWS CLI après le premier apply.
# lifecycle { ignore_changes = [value] } : Terraform ne touche plus la valeur après création.
# Les paramètres infra-dépendants (POSTGRES_HOST, REDIS_URL, REDIS_ADDR, S3_BUCKET_NAME)
# sont gérés dans environments/production/main.tf (calculés automatiquement par Terraform).

# --- Secrets (SecureString) ---

resource "aws_ssm_parameter" "production_secret_key_base" {
  name  = "/chatwoot/production/SECRET_KEY_BASE"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "production_postgres_password" {
  name  = "/chatwoot/production/POSTGRES_PASSWORD"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "production_smtp_password" {
  name  = "/chatwoot/production/SMTP_PASSWORD"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "production_gitlab_registry_token" {
  name  = "/chatwoot/production/GITLAB_REGISTRY_TOKEN"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "production_grafana_password" {
  name  = "/chatwoot/production/GRAFANA_PASSWORD"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

# --- Config (String) ---

resource "aws_ssm_parameter" "production_docker_image_tag" {
  name  = "/chatwoot/production/DOCKER_IMAGE_TAG"
  type  = "String"
  value = "latest"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "production_frontend_url" {
  name  = "/chatwoot/production/FRONTEND_URL"
  type  = "String"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "production_active_storage_service" {
  name  = "/chatwoot/production/ACTIVE_STORAGE_SERVICE"
  type  = "String"
  value = "amazon"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "production_aws_region" {
  name  = "/chatwoot/production/AWS_REGION"
  type  = "String"
  value = "eu-west-3"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "production_redis_openssl_verify_mode" {
  name  = "/chatwoot/production/REDIS_OPENSSL_VERIFY_MODE"
  type  = "String"
  value = "none"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "production_postgres_username" {
  name  = "/chatwoot/production/POSTGRES_USERNAME"
  type  = "String"
  value = "chatwoot"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "production_postgres_db" {
  name  = "/chatwoot/production/POSTGRES_DB"
  type  = "String"
  value = "chatwoot_production"
  tags  = merge(local.tags, { Environment = "production" })
  lifecycle { ignore_changes = [value] }
}
