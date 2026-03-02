variable "env" {
  description = "Environment name"
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket for Chatwoot storage"
  type        = string
}

variable "iam_role_arn" {
  description = "IAM role ARN allowed to access the bucket"
  type        = string
  default     = ""
}

variable "lifecycle_expiration_days" {
  description = "Number of days before objects expire"
  type        = number
  default     = 365
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
