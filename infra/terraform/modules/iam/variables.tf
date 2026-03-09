variable "env" {
  description = "Environment name (production, staging)"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket the EC2 instances need R/W access to."
  type        = string
  default     = ""
}

variable "enable_s3_policy" {
  description = "Enable S3 R/W policy for EC2 instances"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all IAM resources"
  type        = map(string)
  default     = {}
}
