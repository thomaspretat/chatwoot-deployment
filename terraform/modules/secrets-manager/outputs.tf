output "rds_secret_arn" {
  description = "ARN of the RDS credentials secret"
  value       = aws_secretsmanager_secret.rds.arn
}

output "app_secret_arn" {
  description = "ARN of the application env vars secret"
  value       = aws_secretsmanager_secret.app.arn
}

output "all_secret_arns" {
  description = "ARNs of all secrets managed by this module"
  value = concat(
    [aws_secretsmanager_secret.rds.arn, aws_secretsmanager_secret.app.arn],
    [for s in aws_secretsmanager_secret.extra : s.arn]
  )
}
