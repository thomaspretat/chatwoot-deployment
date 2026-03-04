aws_region = "eu-west-3"
env        = "staging"

vpc_cidr            = "10.1.0.0/16"
public_subnet_cidrs = ["10.1.1.0/24"]
availability_zones  = ["eu-west-3a"]

allowed_ssh_cidrs = ["81.49.239.108/32"]

bastion_ami_id        = "ami-0f3f2cef1fc7d0edb"
bastion_instance_type = "t3.micro"

app_ami_id               = "ami-0f3f2cef1fc7d0edb"
app_instance_type        = "t3.small"

monitoring_ami_id        = "ami-0f3f2cef1fc7d0edb"
monitoring_instance_type = "t3.micro"

key_name = "chatwoot-staging"

tags = {
  Project     = "notakaren"
  Environment = "staging"
  ManagedBy   = "terraform"
}
