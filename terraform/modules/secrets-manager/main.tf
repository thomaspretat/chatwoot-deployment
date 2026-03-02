# RDS master credentials secret
resource "aws_secretsmanager_secret" "rds" {
  name        = "chatwoot/${var.env}/rds/master-credentials"
  description = "Chatwoot ${var.env} RDS master credentials"

  recovery_window_in_days = var.env == "production" ? 30 : 0

  tags = merge(var.tags, { Name = "chatwoot/${var.env}/rds" })
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  # Initial empty value — to be populated manually or via a separate process
  secret_string = jsonencode({
    username = ""
    password = ""
    host     = ""
    port     = 5432
    dbname   = ""
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Application secrets (Chatwoot env vars)
resource "aws_secretsmanager_secret" "app" {
  name        = "chatwoot/${var.env}/app/env"
  description = "Chatwoot ${var.env} application environment variables"

  recovery_window_in_days = var.env == "production" ? 30 : 0

  tags = merge(var.tags, { Name = "chatwoot/${var.env}/app" })
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  # Initial empty placeholder — to be populated manually
  secret_string = jsonencode({
    SECRET_KEY_BASE              = ""
    SMTP_PASSWORD                = ""
    AWS_ACCESS_KEY_ID            = ""
    AWS_SECRET_ACCESS_KEY        = ""
    MAILER_SENDER_EMAIL          = ""
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Additional secrets from variable map
resource "aws_secretsmanager_secret" "extra" {
  for_each    = var.secret_names
  name        = "chatwoot/${var.env}/${each.key}"
  description = each.value

  recovery_window_in_days = var.env == "production" ? 30 : 0

  tags = merge(var.tags, { Name = "chatwoot/${var.env}/${each.key}" })
}
