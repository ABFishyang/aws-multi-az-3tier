# ------------------------------------------------------------------
# 設計方針
# 1. ソースにはCIDRではなくセキュリティグループIDを指定する（SGチェーン）。
#    IPアドレスが変わっても設定を追従させる必要がなくなる。
# 2. セキュリティグループはステートフルなので、戻り方向のルールは作らない。
# 3. ALBとEC2は相互参照になるが、Terraformは依存グラフを解決するため
#    CloudFormationのような「循環参照を避けるためインラインルールを
#    別リソース化する」制約は基本的にない。ただし可読性のため、
#    ここでもインラインではなく aws_vpc_security_group_ingress_rule /
#    egress_rule（AWSプロバイダ v5+ の新リソース）を個別に定義している。
# ------------------------------------------------------------------

# ---------- ALB 用 ----------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description        = "HTTP from Internet (redirected to HTTPS when a certificate is configured)"
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol         = "tcp"
  from_port           = 80
  to_port             = 80
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description        = "HTTPS from Internet"
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol         = "tcp"
  from_port           = 443
  to_port             = 443
}

# ---------- EC2 用 ----------
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for Web/App EC2 instances"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.project_name}-ec2-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_to_ec2" {
  security_group_id            = aws_security_group.ec2.id
  description                   = "HTTP from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                   = "tcp"
  from_port                     = 80
  to_port                       = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ec2" {
  security_group_id            = aws_security_group.alb.id
  description                   = "HTTP to EC2 targets"
  referenced_security_group_id = aws_security_group.ec2.id
  ip_protocol                   = "tcp"
  from_port                     = 80
  to_port                       = 80
}

# ---------- RDS 用 ----------
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS MySQL"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.project_name}-rds-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_to_rds" {
  security_group_id            = aws_security_group.rds.id
  description                   = "MySQL from EC2 only"
  referenced_security_group_id = aws_security_group.ec2.id
  ip_protocol                   = "tcp"
  from_port                     = 3306
  to_port                       = 3306
}

# ---------- EFS 用 ----------
resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.project_name}-efs-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_to_efs" {
  security_group_id            = aws_security_group.efs.id
  description                   = "NFS from EC2 only"
  referenced_security_group_id = aws_security_group.ec2.id
  ip_protocol                   = "tcp"
  from_port                     = 2049
  to_port                       = 2049
}

# ---------- VPC エンドポイント (Interface) 用 ----------
resource "aws_security_group" "vpce" {
  name        = "${var.project_name}-vpce-sg"
  description = "Security group for SSM Interface VPC Endpoints"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.project_name}-vpce-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_to_vpce" {
  security_group_id            = aws_security_group.vpce.id
  description                   = "HTTPS from EC2"
  referenced_security_group_id = aws_security_group.ec2.id
  ip_protocol                   = "tcp"
  from_port                     = 443
  to_port                       = 443
}

# RDS/EFS/VPCE はアウトバウンド不要（アプリ側から接続を開始しない）。
# デフォルトの全許可egressを作らないことで最小権限を保つ。
