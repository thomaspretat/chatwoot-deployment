# ─── IAM User (Terraform local + CI/CD) ───────────────────────────

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

# ─── IAM Role pour les instances EC2 ───────────────────────────────

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

# SSM Read (pour lire les paramètres de config au boot)
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

# S3 R/W — uniquement si s3_bucket_arn est fourni (production)
resource "aws_iam_role_policy" "ec2_s3" {
  count = var.s3_bucket_arn != "" ? 1 : 0
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

# Instance Profile (attaché au Launch Template / aws_instance)
resource "aws_iam_instance_profile" "ec2" {
  name = "chatwoot-${var.env}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = merge(var.tags, { Name = "chatwoot-${var.env}-ec2-profile" })
}
