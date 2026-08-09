# ------------------------------------------------------------------
# 設計方針（CloudFormation版からの移植メモ）
# 1. サブネットは3階層 x 2AZ = 6面。Protected層にはデフォルトルートを
#    作らない。RDS/EFSはマネージドサービスで外部通信が不要なため、
#    NATへの経路は攻撃面を増やすだけになる。
# 2. NAT ゲートウェイは AZ ごとに1台ずつ、Private のルートテーブルも
#    AZ ごとに分ける。共有すると片方の NAT にしか向けられず、
#    AZ 障害時にもう一方の AZ まで巻き込まれる。
# 3. NACL は層ごとに分ける（多層防御）。
# 4. Terraform は依存グラフを自動解決するため、CloudFormationの
#    DependsOn（IGWアタッチ待ち等）に相当する記述は基本的に不要。
#    for_each の暗黙の依存関係（IGW→Route→NatGateway）で十分。
# ------------------------------------------------------------------

locals {
  azs = {
    a = var.availability_zones[0]
    b = var.availability_zones[1]
  }

  public_subnets = {
    a = { cidr = var.public_subnet_cidrs[0], az = local.azs.a }
    b = { cidr = var.public_subnet_cidrs[1], az = local.azs.b }
  }
  private_subnets = {
    a = { cidr = var.private_subnet_cidrs[0], az = local.azs.a }
    b = { cidr = var.private_subnet_cidrs[1], az = local.azs.b }
  }
  protected_subnets = {
    a = { cidr = var.protected_subnet_cidrs[0], az = local.azs.a }
    b = { cidr = var.protected_subnet_cidrs[1], az = local.azs.b }
  }
}

# ==================================================================
# VPC / Internet Gateway
# ==================================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# ==================================================================
# Subnets
# ==================================================================
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value.az
  cidr_block               = each.value.cidr
  map_public_ip_on_launch = false # ALB/NATのみ配置。EC2は置かない

  tags = { Name = "${var.project_name}-public-${each.key}", Tier = "public" }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id             = aws_vpc.main.id
  availability_zone   = each.value.az
  cidr_block          = each.value.cidr

  tags = { Name = "${var.project_name}-private-${each.key}", Tier = "private" }
}

resource "aws_subnet" "protected" {
  for_each = local.protected_subnets

  vpc_id             = aws_vpc.main.id
  availability_zone   = each.value.az
  cidr_block          = each.value.cidr

  tags = { Name = "${var.project_name}-protected-${each.key}", Tier = "protected" }
}

# ==================================================================
# NAT Gateway（AZごとに1台 = 冗長構成。1台に減らせば費用は半分になるが
# その AZ が落ちるともう一方の AZ の EC2 も外部通信できなくなる）
# ==================================================================
resource "aws_eip" "nat" {
  for_each = local.public_subnets

  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = { Name = "${var.project_name}-eip-natgw-${each.key}" }
}

resource "aws_nat_gateway" "main" {
  for_each = local.public_subnets

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  depends_on    = [aws_internet_gateway.main]

  tags = { Name = "${var.project_name}-natgw-${each.key}" }
}

# ==================================================================
# Route Tables
# ==================================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-rtb-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id              = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-rtb-private-${each.key}" }
}

resource "aws_route" "private_internet" {
  for_each = local.private_subnets

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id          = aws_nat_gateway.main[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# Protected: 単一ルートテーブルを2AZで共有。デフォルトルートは作らない
# （VPC内部の通信は自動生成される local ルートで完結する）
resource "aws_route_table" "protected" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-rtb-protected" }
}

resource "aws_route_table_association" "protected" {
  for_each = aws_subnet.protected

  subnet_id      = each.value.id
  route_table_id = aws_route_table.protected.id
}

# ==================================================================
# Network ACL - Public（ALBへの80/443とNAT戻り通信のエフェメラルを許可）
# ==================================================================
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  tags = { Name = "${var.project_name}-nacl-public" }
}

resource "aws_network_acl_rule" "public_in_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block      = "0.0.0.0/0"
  from_port       = 443
  to_port         = 443
}

resource "aws_network_acl_rule" "public_in_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block      = "0.0.0.0/0"
  from_port       = 80
  to_port         = 80
}

resource "aws_network_acl_rule" "public_in_ephemeral" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block      = "0.0.0.0/0"
  from_port       = 1024
  to_port         = 65535
}

resource "aws_network_acl_rule" "public_out_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block      = "0.0.0.0/0"
}

# ==================================================================
# Network ACL - Private
# ==================================================================
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [for s in aws_subnet.private : s.id]

  tags = { Name = "${var.project_name}-nacl-private" }
}

resource "aws_network_acl_rule" "private_in_vpc" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block      = var.vpc_cidr
}

resource "aws_network_acl_rule" "private_in_ephemeral" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block      = "0.0.0.0/0"
  from_port       = 1024
  to_port         = 65535
}

resource "aws_network_acl_rule" "private_out_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block      = "0.0.0.0/0"
}

# ==================================================================
# Network ACL - Protected（VPC内部との通信のみ。外部への経路を持たない）
# ==================================================================
resource "aws_network_acl" "protected" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [for s in aws_subnet.protected : s.id]

  tags = { Name = "${var.project_name}-nacl-protected" }
}

resource "aws_network_acl_rule" "protected_in_mysql" {
  network_acl_id = aws_network_acl.protected.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block      = var.vpc_cidr
  from_port       = 3306
  to_port         = 3306
}

resource "aws_network_acl_rule" "protected_in_nfs" {
  network_acl_id = aws_network_acl.protected.id
  rule_number    = 105
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block      = var.vpc_cidr
  from_port       = 2049
  to_port         = 2049
}

resource "aws_network_acl_rule" "protected_in_ephemeral" {
  network_acl_id = aws_network_acl.protected.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block      = var.vpc_cidr
  from_port       = 1024
  to_port         = 65535
}

resource "aws_network_acl_rule" "protected_out_ephemeral" {
  network_acl_id = aws_network_acl.protected.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block      = var.vpc_cidr
  from_port       = 1024
  to_port         = 65535
}

resource "aws_network_acl_rule" "protected_out_mysql" {
  network_acl_id = aws_network_acl.protected.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block      = var.vpc_cidr
  from_port       = 3306
  to_port         = 3306
}

resource "aws_network_acl_rule" "protected_out_nfs" {
  network_acl_id = aws_network_acl.protected.id
  rule_number    = 120
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block      = var.vpc_cidr
  from_port       = 2049
  to_port         = 2049
}
