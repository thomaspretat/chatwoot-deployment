variable "env" {
  description = "Environment name"
  type        = string
}

variable "rds_instance_id" {
  description = "RDS instance ID for rotation"
  type        = string
  default     = ""
}

variable "secret_names" {
  description = "Map of secret names to descriptions"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
