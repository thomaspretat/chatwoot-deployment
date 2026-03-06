terraform {
  backend "s3" {
    bucket         = "chatwoot-batch23-terraform-state"
    key            = "chatwoot/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "chatwoot-terraform-locks"
    encrypt        = true
  }
}
