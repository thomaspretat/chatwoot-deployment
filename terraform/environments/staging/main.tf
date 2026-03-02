terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "chatwoot-terraform-state"
    key            = "environments/staging/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "chatwoot-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

module "networking" {
  source = "../../modules/networking"

  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  enable_nat_gateway   = true
  single_nat_gateway   = true # Cost saving for staging
  tags                 = var.tags
}

module "security_groups" {
  source = "../../modules/security-groups"

  env               = var.env
  vpc_id            = module.networking.vpc_id
  vpc_cidr          = module.networking.vpc_cidr
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  tags              = var.tags
}

module "iam" {
  source = "../../modules/iam"

  env           = var.env
  s3_bucket_arn = module.s3.bucket_arn
  secrets_arns  = module.secrets_manager.all_secret_arns
  tags          = var.tags
}

module "secrets_manager" {
  source = "../../modules/secrets-manager"

  env  = var.env
  tags = var.tags
}

module "acm" {
  source = "../../modules/acm"

  domain_name = var.domain_name
  zone_id     = var.route53_zone_id
  tags        = var.tags
}

module "s3" {
  source = "../../modules/s3"

  env          = var.env
  bucket_name  = var.s3_bucket_name
  iam_role_arn = module.iam.role_arn
  tags         = var.tags
}

module "rds" {
  source = "../../modules/rds"

  env               = var.env
  instance_class    = var.rds_instance_class
  subnet_ids        = module.networking.private_subnet_ids
  security_group_id = module.security_groups.rds_sg_id
  db_password       = var.rds_db_password
  multi_az          = false # Single-AZ for staging
  deletion_protection = false
  backup_retention_period = 3
  tags              = var.tags
}

module "elasticache" {
  source = "../../modules/elasticache"

  env                        = var.env
  node_type                  = var.redis_node_type
  num_cache_clusters         = 1
  subnet_ids                 = module.networking.private_subnet_ids
  security_group_id          = module.security_groups.redis_sg_id
  automatic_failover_enabled = false
  multi_az_enabled           = false
  tags                       = var.tags
}

module "bastion" {
  source = "../../modules/bastion"

  env               = var.env
  ami_id            = var.bastion_ami_id
  instance_type     = var.bastion_instance_type
  key_name          = var.key_name
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = module.security_groups.bastion_sg_id
  instance_count    = 1 # Single bastion for staging
  tags              = var.tags
}

module "alb" {
  source = "../../modules/alb"

  env               = var.env
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  security_group_id = module.security_groups.alb_sg_id
  certificate_arn   = module.acm.certificate_arn
  tags              = var.tags
}

# Staging uses a static EC2 instead of ASG
module "ec2" {
  source = "../../modules/ec2"

  env                  = var.env
  ami_id               = var.app_ami_id
  instance_type        = var.app_instance_type
  key_name             = var.key_name
  subnet_id            = module.networking.private_subnet_ids[0]
  security_group_id    = module.security_groups.ec2_sg_id
  iam_instance_profile = module.iam.instance_profile_name
  target_group_arn     = module.alb.target_group_arn
  tags                 = var.tags
}

module "route53" {
  source = "../../modules/route53"

  zone_id      = var.route53_zone_id
  domain_name  = var.domain_name
  alb_dns_name = module.alb.alb_dns_name
  alb_zone_id  = module.alb.alb_zone_id
  tags         = var.tags
}
