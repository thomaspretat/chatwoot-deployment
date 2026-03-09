# Elastic IPs — Staging (persistent, survive destroy/apply)
resource "aws_eip" "staging_monitoring" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "chatwoot-staging-monitoring-eip", Environment = "staging" })
}

resource "aws_eip" "staging_app" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "chatwoot-staging-app-eip", Environment = "staging" })
}

output "staging_monitoring_eip_id" { value = aws_eip.staging_monitoring.id }
output "staging_app_eip_id" { value = aws_eip.staging_app.id }
output "staging_monitoring_public_ip" { value = aws_eip.staging_monitoring.public_ip }
output "staging_app_public_ip" { value = aws_eip.staging_app.public_ip }

# SSM Parameter Store — Staging
# Valeurs par défaut "TO_FILL" : à remplir via AWS CLI après le premier apply.
# lifecycle { ignore_changes = [value] } : Terraform ne touche plus la valeur après création.

# --- Secrets (SecureString) ---

resource "aws_ssm_parameter" "staging_secret_key_base" {
  name  = "/chatwoot/staging/SECRET_KEY_BASE"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_postgres_password" {
  name  = "/chatwoot/staging/POSTGRES_PASSWORD"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_redis_password" {
  name  = "/chatwoot/staging/REDIS_PASSWORD"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_smtp_password" {
  name  = "/chatwoot/staging/SMTP_PASSWORD"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_gitlab_registry_token" {
  name  = "/chatwoot/staging/GITLAB_REGISTRY_TOKEN"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_grafana_password" {
  name  = "/chatwoot/staging/GRAFANA_PASSWORD"
  type  = "SecureString"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

# --- Config (String) ---

resource "aws_ssm_parameter" "staging_docker_image_tag" {
  name  = "/chatwoot/staging/DOCKER_IMAGE_TAG"
  type  = "String"
  value = "latest"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_frontend_url" {
  name  = "/chatwoot/staging/FRONTEND_URL"
  type  = "String"
  value = "TO_FILL"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_postgres_host" {
  name  = "/chatwoot/staging/POSTGRES_HOST"
  type  = "String"
  value = "postgres"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_redis_url" {
  name  = "/chatwoot/staging/REDIS_URL"
  type  = "String"
  value = "redis://redis:6379"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_postgres_username" {
  name  = "/chatwoot/staging/POSTGRES_USERNAME"
  type  = "String"
  value = "chatwoot"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_postgres_db" {
  name  = "/chatwoot/staging/POSTGRES_DB"
  type  = "String"
  value = "chatwoot_staging"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_active_storage_service" {
  name  = "/chatwoot/staging/ACTIVE_STORAGE_SERVICE"
  type  = "String"
  value = "local"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "staging_force_ssl" {
  name  = "/chatwoot/staging/FORCE_SSL"
  type  = "String"
  value = "false"
  tags  = merge(local.tags, { Environment = "staging" })
  lifecycle { ignore_changes = [value] }
}
