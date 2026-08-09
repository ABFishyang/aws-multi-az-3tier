# ------------------------------------------------------------------
# 設計方針
# 1. 踏み台サーバーを置かず Session Manager で接続する。
#    そのために ssm / ssmmessages / ec2messages の3つが必要。
#    1つでも欠けるとセッションが確立できない。
# 2. S3 は Gateway 型を使う。Interface型と違い時間課金もデータ処理料も
#    無料で、NATゲートウェイのデータ処理料を削減できる。dnf のパッケージ
#    取得はS3経由なので効果が大きい。
# ------------------------------------------------------------------

locals {
  interface_services = ["ssm", "ssmmessages", "ec2messages"]
}

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_services)

  vpc_id              = var.vpc_id
  service_name         = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type    = "Interface"
  private_dns_enabled  = true
  subnet_ids           = var.private_subnet_ids
  security_group_ids   = [var.vpce_security_group_id]

  tags = { Name = "${var.project_name}-vpce-${each.value}" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id             = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = var.private_route_table_ids

  tags = { Name = "${var.project_name}-vpce-s3" }
}
