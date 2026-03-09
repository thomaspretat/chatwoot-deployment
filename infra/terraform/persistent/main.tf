terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "chatwoot-batch23-terraform-state"
    key            = "persistent/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "chatwoot-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "eu-west-3"
}

locals {
  tags = {
    Project   = "notakaren"
    ManagedBy = "terraform"
  }
}
