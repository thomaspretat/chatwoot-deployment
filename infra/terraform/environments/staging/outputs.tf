output "vpc_id" {
  description = "ID of the staging VPC"
  value       = module.networking.vpc_id
}

output "bastion_public_ip" {
  description = "Public IP of the bastion (stable Elastic IP) — SSH entry point"
  value       = aws_eip.bastion.public_ip
}

output "app_public_ip" {
  description = "Public IP of the Chatwoot EC2 (stable Elastic IP)"
  value       = aws_eip.app.public_ip
}

output "app_private_ip" {
  description = "Private IP of the Chatwoot EC2 — for SSH via bastion"
  value       = aws_instance.app.private_ip
}

output "monitoring_public_ip" {
  description = "Public IP of the monitoring EC2 — Grafana and Prometheus"
  value       = aws_instance.monitoring.public_ip
}

output "grafana_url" {
  description = "Grafana URL (access restricted to team IPs)"
  value       = "http://${aws_instance.monitoring.public_ip}:3000"
}

output "chatwoot_url" {
  description = "URL Chatwoot staging"
  value       = "https://staging-chatwoot.thomaspretat.com"
}

output "app_instance_id" {
  description = "EC2 instance ID of the app (useful for SSM commands)"
  value       = aws_instance.app.id
}

output "monitoring_instance_id" {
  description = "EC2 instance ID of the monitoring instance"
  value       = aws_instance.monitoring.id
}

output "iam_user_name" {
  description = "IAM user for Terraform / CI/CD"
  value       = module.iam.iam_user_name
}

output "iam_access_key_id" {
  description = "Access key ID (à configurer dans AWS CLI / CI/CD)"
  value       = module.iam.iam_access_key_id
}

output "iam_secret_access_key" {
  description = "Secret access key (sensible — récupérer via: terraform output -raw iam_secret_access_key)"
  value       = module.iam.iam_secret_access_key
  sensitive   = true
}
