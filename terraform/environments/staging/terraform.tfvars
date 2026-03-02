aws_region = "eu-west-3"
env        = "staging"

vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
availability_zones   = ["eu-west-3a", "eu-west-3b"]

allowed_ssh_cidrs = ["YOUR_OFFICE_IP/32"]

bastion_ami_id        = "ami-xxxxxxxxxxxxxxxxx"
app_ami_id            = "ami-xxxxxxxxxxxxxxxxx"
bastion_instance_type = "t3.micro"
app_instance_type     = "t3.small"
key_name              = "chatwoot-staging"

rds_instance_class = "db.t3.small"
redis_node_type    = "cache.t3.micro"

s3_bucket_name = "chatwoot-staging-storage"

domain_name     = "staging.chatwoot.example.com"
route53_zone_id = "ZXXXXXXXXXXXXXXXXX"

tags = {
  Project     = "chatwoot"
  Environment = "staging"
  ManagedBy   = "terraform"
}
