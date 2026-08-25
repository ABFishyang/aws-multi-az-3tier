# ------------------------------------------------------------------
# 設計方針
# 1. schedule は必ず指定する。CloudFormation版のレビューで実際に検出
#    した不具合パターン ―― プランもルールも作成されるがscheduleが
#    無いとバックアップは一度も自動実行されず、コンソール上は
#    正常に見える ―― を踏まえ、tflintの構文チェックだけでは防げない
#    ため required にしている（default値を持たせない）。
# 2. 対象はタグで選択する。インスタンスARNを直接列挙すると、
#    インスタンスを再作成するたびに書き換えが必要になる。
# 3. RDSも対象に含める（AWS Backup で一元管理する）。
# ------------------------------------------------------------------

resource "aws_backup_vault" "main" {
  name = "${var.project_name}-vault"

  # CloudFormation版の DeletionPolicy: Retain に相当。誤って
  # terraform destroy してもバックアップボールトは残す。
  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.project_name}-vault" }
}

resource "aws_backup_plan" "daily" {
  name = "${var.project_name}-daily-plan"

  rule {
    rule_name                    = "DailyBackup"
    target_vault_name            = aws_backup_vault.main.name
    schedule                     = var.backup_schedule
    schedule_expression_timezone = "Asia/Tokyo"
    start_window                 = 60
    completion_window            = 180

    lifecycle {
      delete_after = var.delete_after_days
    }

    recovery_point_tags = {
      Project = var.project_name
    }
  }
}

resource "aws_backup_selection" "tagged" {
  name         = "${var.project_name}-tagged-resources"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = var.backup_role_arn

  # EC2はタグで、RDSはARNで明示的に対象にする（AWS BackupのSelectionでは
  # selection_tag と resources は OR で結合される）
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }

  resources = [var.db_instance_arn]
}
