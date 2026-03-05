variable "env" {
  description = "Environment name (production, staging)"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket the EC2 instances need R/W access to. Leave empty to skip S3 policy."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all IAM resources"
  type        = map(string)
  default     = {}
}
