variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
  default     = "chatwoot-batch23-terraform-state"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
  default     = "chatwoot-terraform-locks"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default = {
    Project   = "chatwoot"
    ManagedBy = "terraform"
  }
}
