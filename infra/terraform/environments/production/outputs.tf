output "vpc_id" {
  description = "ID of the production VPC"
  value       = module.networking.vpc_id
}

output "alb_dns_name" {
  description = "DNS name of the ALB — CNAME chatwoot.thomaspretat.com → this value in Cloudflare"
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

output "bastion_public_ip" {
  description = "Public IP of the bastion"
  value       = aws_instance.bastion.public_ip
}

output "asg_name" {
  description = "ASG name — for SSM and Instance Refresh in the CI pipeline"
  value       = aws_autoscaling_group.this.name
}

output "acm_validation_record" {
  description = "CNAME to add in Cloudflare for ACM certificate validation"
  value = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      value  = dvo.resource_record_value
    }
  }
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
