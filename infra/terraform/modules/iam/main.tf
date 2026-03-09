# IAM User (Terraform local + CI/CD)

resource "aws_iam_user" "chatwoot" {
  name = "chatwoot-${var.env}"
  tags = merge(var.tags, { Name = "chatwoot-${var.env}" })
}

resource "aws_iam_user_policy_attachment" "chatwoot_admin" {
  user       = aws_iam_user.chatwoot.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_access_key" "chatwoot" {
  user = aws_iam_user.chatwoot.name
}

# IAM Role pour les instances EC2

resource "aws_iam_role" "ec2" {
  name = "chatwoot-${var.env}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-ec2-role" })
}

# SSM Read — scopé à /chatwoot/{env}/* uniquement
resource "aws_iam_role_policy" "ec2_ssm" {
  name = "chatwoot-${var.env}-ec2-ssm"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ]
      Resource = "arn:aws:ssm:*:*:parameter/chatwoot/${var.env}/*"
    }]
  })
}

# S3 R/W — uniquement si s3_bucket_arn est fourni (production)
resource "aws_iam_role_policy" "ec2_s3" {
  count = var.enable_s3_policy ? 1 : 0
  name  = "chatwoot-${var.env}-ec2-s3"
  role  = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        var.s3_bucket_arn,
        "${var.s3_bucket_arn}/*"
      ]
    }]
  })
}

# ec2:DescribeTags — nécessaire pour que chatwoot-start.sh lise le tag Environment et ec2:DescribeInstances pour monitorer (get les instances via ec2_sd_configs)
resource "aws_iam_role_policy" "ec2_describe_tags" {
  name = "chatwoot-${var.env}-ec2-describe-tags"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeTags", "ec2:DescribeInstances"]
      Resource = "*"
    }]
  })
}

# Instance Profile (attaché au Launch Template / aws_instance)
resource "aws_iam_instance_profile" "ec2" {
  name = "chatwoot-${var.env}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = merge(var.tags, { Name = "chatwoot-${var.env}-ec2-profile" })
}
