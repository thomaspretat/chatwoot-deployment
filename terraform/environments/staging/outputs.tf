output "vpc_id" {
  description = "ID of the staging VPC"
  value       = module.networking.vpc_id
}

output "bastion_public_ip" {
  description = "IP publique du bastion (Elastic IP stable) — point d'entrée SSH"
  value       = aws_eip.bastion.public_ip
}

output "app_public_ip" {
  description = "IP publique de l'EC2 Chatwoot — accès HTTP et SSH"
  value       = aws_instance.app.public_ip
}

output "monitoring_public_ip" {
  description = "IP publique de l'EC2 monitoring — Grafana et Prometheus"
  value       = aws_instance.monitoring.public_ip
}

output "grafana_url" {
  description = "URL Grafana (accès restreint aux IPs de l'équipe)"
  value       = "http://${aws_instance.monitoring.public_ip}:3000"
}

output "chatwoot_url" {
  description = "URL Chatwoot staging"
  value       = "http://${aws_instance.app.public_ip}"
}

output "app_instance_id" {
  description = "EC2 instance ID de l'app (utile pour les commandes SSM)"
  value       = aws_instance.app.id
}

output "monitoring_instance_id" {
  description = "EC2 instance ID du monitoring"
  value       = aws_instance.monitoring.id
}
