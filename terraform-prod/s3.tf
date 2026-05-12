############################################################
# S3 - Loki / Tempo storage backends
#
# Loki: chunks (logs)
# Tempo: blocks (traces)
#
# Lifecycle policy 로 cold storage 이전 + 만료 자동화
############################################################

resource "aws_s3_bucket" "loki" {
  bucket = "${local.name_prefix}-loki-chunks"

  tags = { Name = "${local.name_prefix}-loki-chunks" }
}

resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id
  versioning_configuration {
    status = "Disabled"   # log chunks 는 immutable, versioning 불필요
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration {
      days = 365
    }
  }
}

############################################################
# Tempo
############################################################
resource "aws_s3_bucket" "tempo" {
  bucket = "${local.name_prefix}-tempo-blocks"

  tags = { Name = "${local.name_prefix}-tempo-blocks" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  rule {
    id     = "expire-traces"
    status = "Enabled"

    filter {}

    # trace 는 historical 가치 낮음 - 30일이면 충분
    expiration {
      days = 30
    }
  }
}
