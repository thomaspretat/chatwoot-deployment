output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.chatwoot.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.chatwoot.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.chatwoot.bucket_regional_domain_name
}
