output "instance_profile_name" {
  description = "Name of the EC2 IAM instance profile"
  value       = aws_iam_instance_profile.ec2.name
}

output "iam_user_name" {
  description = "IAM user name for Terraform / CI/CD"
  value       = aws_iam_user.chatwoot.name
}

output "iam_access_key_id" {
  description = "Access key ID for the IAM user"
  value       = aws_iam_access_key.chatwoot.id
}

output "iam_secret_access_key" {
  description = "Secret access key for the IAM user (sensitive)"
  value       = aws_iam_access_key.chatwoot.secret
  sensitive   = true
}
