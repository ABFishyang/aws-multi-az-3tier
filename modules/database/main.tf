# ------------------------------------------------------------------
# 設計方針
# 1. manage_master_user_password = true を使う。RDS が Secrets Manager
#    にシークレットを自動生成し、ローテーションまで管理する。
#    Terraformコード・tfstate・Gitのいずれにも平文パスワードは
#    現れない（tfstate には Secrets Manager の ARN のみが記録される）。
# 2. storage_encrypted = true。作成後の変更にはスナップショット経由の
#    再作成が必要になるため、最初から入れる。
# 3. engine_version はパラメータ化する。マイナーバージョンを固定すると
#    サポート終了時に作成できなくなる。
# 4. deletion_protection は既定 false。true にすると
#    terraform destroy が失敗して削除できず課金が続く。
# ------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.project_name}-db-"
  description = "Subnet group for RDS in protected subnets"
  subnet_ids  = var.protected_subnet_ids

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.project_name}-db-"
  description = "Parameter group for MySQL"
  family      = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }
  parameter {
    name  = "time_zone"
    value = "Asia/Tokyo"
  }

  tags = { Name = "${var.project_name}-db-pg" }
}

resource "aws_db_instance" "main" {
  identifier        = "${var.project_name}-mysql"
  engine            = "mysql"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.master_username
  # パスワードは RDS が生成し Secrets Manager で管理する
  manage_master_user_password = true

  multi_az               = var.multi_az
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]

  backup_retention_period         = var.backup_retention_period
  backup_window                   = "17:00-18:00"
  maintenance_window              = "sun:18:00-sun:19:00"
  auto_minor_version_upgrade      = true
  deletion_protection             = var.deletion_protection
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  copy_tags_to_snapshot           = true

  # CloudFormation版の DeletionPolicy: Snapshot に相当。deletion_protection
  # とは独立した設定で、destroy時は常に最終スナップショットを残す。
  # 同名スナップショットの衝突を避けたい場合は識別子にサフィックスを足すこと。
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-mysql-final"

  tags = { Name = "${var.project_name}-mysql" }
}
