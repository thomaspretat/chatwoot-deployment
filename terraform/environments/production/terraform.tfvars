aws_region = "eu-west-3"
env        = "production"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
availability_zones   = ["eu-west-3a", "eu-west-3b"]

allowed_ssh_cidrs = ["YOUR_OFFICE_IP/32"]

bastion_ami_id        = "ami-xxxxxxxxxxxxxxxxx"
app_ami_id            = "ami-xxxxxxxxxxxxxxxxx"
bastion_instance_type = "t3.micro"
app_instance_type     = "t3.medium"
key_name              = "chatwoot-production"

asg_desired_capacity = 2
asg_min_size         = 2
asg_max_size         = 6

rds_instance_class = "db.t3.medium"
redis_node_type    = "cache.t3.small"

s3_bucket_name = "chatwoot-production-storage"

domain_name     = "app.chatwoot.example.com"
route53_zone_id = "ZXXXXXXXXXXXXXXXXX"

tags = {
  Project     = "chatwoot"
  Environment = "production"
  ManagedBy   = "terraform"
}
