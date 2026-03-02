variable "env" {
  description = "Environment name"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the Chatwoot S3 bucket"
  type        = string
}

variable "secrets_arns" {
  description = "ARNs of Secrets Manager secrets the EC2 can read"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
