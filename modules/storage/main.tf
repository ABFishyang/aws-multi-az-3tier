# ------------------------------------------------------------------
# 設計方針
# 1. encrypted = true で保存時暗号化を有効にする。作成後には変更
#    できないため最初から指定する。
# 2. マウントターゲットは Protected サブネットに置く。
# 3. EC2側は amazon-efs-utils による mount -t efs -o tls で接続する
#    （user_data 側の実装。転送時暗号化を必須にするファイルシステム
#    ポリシーをここで強制する）。
# ------------------------------------------------------------------

resource "aws_efs_file_system" "main" {
  encrypted        = true
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode

  lifecycle_policy {
    transition_to_ia                    = "AFTER_30_DAYS"
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = { Name = "${var.project_name}-efs" }
}

resource "aws_efs_backup_policy" "main" {
  file_system_id = aws_efs_file_system.main.id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_file_system_policy" "enforce_tls" {
  file_system_id = aws_efs_file_system.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTlsInTransit"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "*"
        Resource  = aws_efs_file_system.main.arn
        Condition = {
          Bool = {
            "elasticfilesystem:AccessedViaMountTarget" = "true"
            "aws:SecureTransport"                      = "false"
          }
        }
      }
    ]
  })
}

resource "aws_efs_mount_target" "main" {
  for_each = var.protected_subnet_ids

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = each.value
  security_groups = [var.efs_security_group_id]
}
