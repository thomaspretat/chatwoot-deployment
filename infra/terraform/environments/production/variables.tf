variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to the bastion"
  type        = list(string)
}

variable "bastion_ami_id" {
  description = "AMI ID for the bastion instance"
  type        = string
}

variable "app_ami_id" {
  description = "AMI ID for the application instances"
  type        = string
}

variable "bastion_instance_type" {
  description = "Instance type for bastion"
  type        = string
  default     = "t3.micro"
}

variable "app_instance_type" {
  description = "Instance type for application ASG"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 2
}

variable "asg_min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 6
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "rds_db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for Chatwoot storage"
  type        = string
}

variable "domain_name" {
  description = "Primary domain name"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
