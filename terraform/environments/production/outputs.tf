output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = module.alb.alb_dns_name
}

output "app_url" {
  description = "Application URL"
  value       = "https://${module.route53.fqdn}"
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.endpoint
}

output "rds_address" {
  description = "RDS hostname"
  value       = module.rds.address
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint"
  value       = module.elasticache.primary_endpoint_address
}

output "s3_bucket_name" {
  description = "S3 bucket name for Chatwoot storage"
  value       = module.s3.bucket_name
}

output "bastion_public_ips" {
  description = "Public IPs of the bastion hosts"
  value       = module.bastion.public_ips
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.asg.asg_name
}

output "rds_secret_arn" {
  description = "ARN of the RDS secret in Secrets Manager"
  value       = module.secrets_manager.rds_secret_arn
}
