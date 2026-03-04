output "vpc_id" {
  description = "ID of the production VPC"
  value       = module.networking.vpc_id
}

output "alb_dns_name" {
  description = "DNS name of the ALB (à pointer dans Route53)"
  value       = aws_lb.this.dns_name
}

output "rds_endpoint" {
  description = "RDS endpoint (host:port) — à stocker dans Secrets Manager"
  value       = aws_db_instance.this.endpoint
}

output "rds_address" {
  description = "RDS hostname seul — pour POSTGRES_HOST dans .env"
  value       = aws_db_instance.this.address
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint — pour REDIS_URL dans .env (utiliser rediss://)"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "s3_bucket_name" {
  description = "S3 bucket name pour ACTIVE_STORAGE_SERVICE=amazon"
  value       = aws_s3_bucket.chatwoot.bucket
}

output "bastion_public_ips" {
  description = "IPs publiques des bastions (AZ-a et AZ-b)"
  value       = aws_eip.bastion[*].public_ip
}

output "asg_name" {
  description = "Nom de l'ASG — pour SSM et Instance Refresh dans le pipeline CI"
  value       = aws_autoscaling_group.this.name
}

output "ssm_parameter_path" {
  description = "Chemin racine des paramètres SSM pour cet environnement"
  value       = "/chatwoot/${var.env}"
}
