output "vpc_id" {
  description = "ID of the production VPC"
  value       = module.networking.vpc_id
}

output "alb_dns_name" {
  description = "DNS name of the ALB (to point to in Route53)"
  value       = aws_lb.this.dns_name
}

output "rds_endpoint" {
  description = "RDS endpoint (host:port) — to store in Secrets Manager"
  value       = aws_db_instance.this.endpoint
}

output "rds_address" {
  description = "RDS hostname only — for POSTGRES_HOST in .env"
  value       = aws_db_instance.this.address
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint — for REDIS_URL in .env (use rediss://)"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "s3_bucket_name" {
  description = "S3 bucket name for ACTIVE_STORAGE_SERVICE=amazon"
  value       = aws_s3_bucket.chatwoot.bucket
}

output "bastion_public_ips" {
  description = "Public IPs of the bastions (AZ-a and AZ-b)"
  value       = aws_eip.bastion[*].public_ip
}

output "asg_name" {
  description = "ASG name — for SSM and Instance Refresh in the CI pipeline"
  value       = aws_autoscaling_group.this.name
}

output "ssm_parameter_path" {
  description = "Root path of SSM parameters for this environment"
  value       = "/chatwoot/${var.env}"
}

output "route53_nameservers" {
  description = "NS records to set at your registrar to delegate DNS to Route53"
  value       = aws_route53_zone.this.name_servers
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
