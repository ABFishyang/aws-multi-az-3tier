# ------------------------------------------------------------------
# 設計方針
# 1. バケットポリシーの Principal にはサービスプリンシパルを使う
#    （logdelivery.elasticloadbalancing.amazonaws.com / delivery.logs.amazonaws.com）。
# 2. 許可パスと実際の配信先プレフィックスを一致させる。ここがずれると
#    ログは静かに配信されない（エラーが出ない）。
# 3. ライフサイクルルールで自動削除する。ログは放置すると増え続ける。
# 4. Terraformは単一の依存グラフで解決するため、CloudFormationのような
#    「05-loggingを09-loadbalancerより先にデプロイする」という
#    スタック順序上の制約そのものがない。ALBリソース側で
#    このモジュールのbucket policyに対する暗黙の依存（aws_s3_bucket_policy
#    への参照）を持たせれば、terraform apply 1回で順序も解決される。
# ------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.project_name}-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  # CloudFormation版の DeletionPolicy: Retain に相当。ログは監査証跡になるため
  # 誤った terraform destroy から保護する。本当に削除する場合は、この
  # lifecycle ブロックを一旦外してから destroy すること。
  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.project_name}-logs" }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      # ALBアクセスログは SSE-S3 のみ対応（KMSカスタマーキーは不可）
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_retention_days
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAlbLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/${var.alb_log_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AllowFlowLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/${var.flow_log_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AllowFlowLogAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })
}

resource "aws_flow_log" "vpc" {
  # バケットポリシーが先に存在しないと配信設定の検証に失敗する
  depends_on = [aws_s3_bucket_policy.logs]

  vpc_id               = var.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  # ポリシーで許可したパスと必ず一致させること
  log_destination          = "${aws_s3_bucket.logs.arn}/${var.flow_log_prefix}/"
  max_aggregation_interval = 600

  tags = { Name = "${var.project_name}-vpc-flowlog" }
}
