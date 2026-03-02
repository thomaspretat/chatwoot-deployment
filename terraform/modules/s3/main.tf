resource "aws_s3_bucket" "chatwoot" {
  bucket = var.bucket_name
  tags   = merge(var.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_versioning" "chatwoot" {
  bucket = aws_s3_bucket.chatwoot.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "chatwoot" {
  bucket = aws_s3_bucket.chatwoot.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "chatwoot" {
  bucket                  = aws_s3_bucket.chatwoot.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "chatwoot" {
  bucket = aws_s3_bucket.chatwoot.id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "chatwoot" {
  count  = var.iam_role_arn != "" ? 1 : 0
  bucket = aws_s3_bucket.chatwoot.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = var.iam_role_arn }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.chatwoot.arn,
          "${aws_s3_bucket.chatwoot.arn}/*"
        ]
      }
    ]
  })
}
