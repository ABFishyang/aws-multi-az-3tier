# ------------------------------------------------------------------
# 設計方針
# 1. CloudWatchAgentServerPolicy を使う（Adminではない）。メトリクス送信
#    だけのWebサーバーには書き込み権限を含むAdmin版は過剰。
# 2. Secrets Manager は特定シークレットのみに限定したインラインポリシー。
# 3. EFSクライアント権限は ClientMount/ClientWrite のみとし、
#    ClientRootAccess（UID/GID強制を素通りする権限）は付与しない。
#    Resourceもアカウント/リージョン内のEFSに限定する。
# 4. 物理名（RoleNameなど）は指定しない。Terraformはリソース置換時に
#    create_before_destroy 等で制御できるが、名前固定は同名衝突の
#    リスクを増やすだけなので避ける。
# ------------------------------------------------------------------

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "ec2" {
  name_prefix = "${var.project_name}-ec2-"
  description = "Allows Web/App EC2 instances to use Systems Manager, CloudWatch Agent, and read the RDS secret"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = { Name = "${var.project_name}-ec2-role" }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "read_db_secret" {
  name = "read-db-secret"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        # RDS のマネージドシークレットは rds!db-xxxx という名前で作られる
        Resource = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:rds!db-*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "efs_client_access" {
  name = "efs-client-access"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:elasticfilesystem:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:file-system/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "${var.project_name}-ec2-"
  role        = aws_iam_role.ec2.name
}

# ---------- AWS Backup 用サービスロール ----------
resource "aws_iam_role" "backup" {
  name_prefix = "${var.project_name}-backup-"
  description = "Used by AWS Backup to back up and restore tagged resources"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "backup.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = { Name = "${var.project_name}-backup-role" }
}

resource "aws_iam_role_policy_attachment" "backup_for_backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_for_restores" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}
