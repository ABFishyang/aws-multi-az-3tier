# ==================================================================
# UserData のレンダリング
# CloudFormation版は Fn::Base64/Fn::Sub をテンプレートの中に直接書いて
# いたが、Terraformでは templatefile() でレンダリングした文字列を
# 変数として compute モジュールに渡す（モジュール自身がファイルパスに
# 依存しないようにするため）。
# ==================================================================
locals {
  web_user_data = templatefile("${path.module}/user_data/web-server.sh.tftpl", {
    efs_id     = module.storage.file_system_id
    db_host    = module.database.db_endpoint_address
    db_name    = module.database.db_name
    secret_arn  = module.database.db_secret_arn
    region      = var.aws_region
  })
}

# ==================================================================
# 01: network
# ==================================================================
module "network" {
  source = "./modules/network"

  project_name             = var.project_name
  vpc_cidr                  = var.vpc_cidr
  availability_zones        = var.availability_zones
  public_subnet_cidrs        = var.public_subnet_cidrs
  private_subnet_cidrs       = var.private_subnet_cidrs
  protected_subnet_cidrs     = var.protected_subnet_cidrs
}

# ==================================================================
# 02: security
# ==================================================================
module "security" {
  source = "./modules/security"

  project_name = var.project_name
  vpc_id        = module.network.vpc_id
}

# ==================================================================
# 03: iam
# ==================================================================
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
}

# ==================================================================
# 04: endpoints
# ==================================================================
module "endpoints" {
  source = "./modules/endpoints"

  project_name              = var.project_name
  vpc_id                     = module.network.vpc_id
  private_subnet_ids          = values(module.network.private_subnet_ids)
  private_route_table_ids     = values(module.network.private_route_table_ids)
  vpce_security_group_id      = module.security.vpce_security_group_id
}

# ==================================================================
# 05: logging
# ==================================================================
module "logging" {
  source = "./modules/logging"

  project_name      = var.project_name
  vpc_id             = module.network.vpc_id
  alb_log_prefix      = var.alb_log_prefix
  flow_log_prefix     = var.flow_log_prefix
  log_retention_days  = var.log_retention_days
}

# ==================================================================
# 06: storage (EFS)
# ==================================================================
module "storage" {
  source = "./modules/storage"

  project_name            = var.project_name
  protected_subnet_ids      = module.network.protected_subnet_ids
  efs_security_group_id     = module.security.efs_security_group_id
  performance_mode           = var.efs_performance_mode
  throughput_mode             = var.efs_throughput_mode
}

# ==================================================================
# 07: database (RDS)
# ==================================================================
module "database" {
  source = "./modules/database"

  project_name              = var.project_name
  protected_subnet_ids        = values(module.network.protected_subnet_ids)
  rds_security_group_id       = module.security.rds_security_group_id
  instance_class                = var.db_instance_class
  engine_version                 = var.db_engine_version
  allocated_storage              = var.db_allocated_storage
  db_name                        = var.db_name
  master_username                = var.db_master_username
  multi_az                       = var.db_multi_az
  backup_retention_period        = var.db_backup_retention_period
  deletion_protection            = var.db_deletion_protection
}

# ==================================================================
# 08: compute (EC2 web servers)
# ==================================================================
module "compute" {
  source = "./modules/compute"

  project_name                = var.project_name
  private_subnet_ids            = module.network.private_subnet_ids
  ec2_security_group_id         = module.security.ec2_security_group_id
  iam_instance_profile_name      = module.iam.ec2_instance_profile_name
  instance_type                   = var.instance_type
  root_volume_size                 = var.root_volume_size
  enable_detailed_monitoring       = var.enable_detailed_monitoring
  user_data                        = local.web_user_data
}

# ==================================================================
# 09-a: dns（証明書の発行・検証のみ。ALBへの依存を持たない）
# ==================================================================
module "dns" {
  source = "./modules/dns"

  project_name    = var.project_name
  domain_name      = var.domain_name
  hosted_zone_id   = var.hosted_zone_id
}

# ==================================================================
# 09-b: loadbalancer（証明書ARNを dns モジュールから受け取る）
# ==================================================================
module "loadbalancer" {
  source = "./modules/loadbalancer"

  project_name          = var.project_name
  vpc_id                  = module.network.vpc_id
  public_subnet_ids        = values(module.network.public_subnet_ids)
  alb_security_group_id    = module.security.alb_security_group_id
  web_instance_ids          = module.compute.instance_ids
  certificate_arn           = module.dns.certificate_arn
  health_check_path         = var.health_check_path
  enable_access_logs        = var.enable_access_logs
  log_bucket_name            = module.logging.log_bucket_name
  alb_log_prefix             = module.logging.alb_log_prefix

  # ALBのアクセスログ有効時、バケットポリシーが先に存在しないと
  # ALB作成自体が失敗する。logging モジュール全体（ポリシーを含む）の
  # 完了を明示的に待つ。
  depends_on = [module.logging]
}

# ==================================================================
# 09-c: dns alias record（証明書・ALB双方に依存する「最後の一手」。
# dns モジュールと loadbalancer モジュールを直接相互参照させると
# Terraformの依存グラフが循環してしまうため、ここに置くことで
# dns → loadbalancer → alias という一方向の依存関係にしている）
# ==================================================================
resource "aws_route53_record" "alias" {
  count = var.domain_name != "" ? 1 : 0

  zone_id  = var.hosted_zone_id
  name      = var.domain_name
  type      = "A"

  alias {
    name                   = module.loadbalancer.alb_dns_name
    zone_id                 = module.loadbalancer.alb_zone_id
    evaluate_target_health  = true
  }
}

# ==================================================================
# 11: monitoring
# ==================================================================
module "monitoring" {
  source = "./modules/monitoring"

  project_name              = var.project_name
  notification_email          = var.notification_email
  web_instance_ids             = module.compute.instance_ids
  target_group_arn_suffix       = module.loadbalancer.target_group_arn_suffix
  alb_arn_suffix                 = module.loadbalancer.alb_arn_suffix
  db_instance_identifier         = module.database.db_instance_identifier
  cpu_alarm_threshold             = var.cpu_alarm_threshold
}

# ==================================================================
# 12: backup
# ==================================================================
module "backup" {
  source = "./modules/backup"

  project_name        = var.project_name
  backup_role_arn        = module.iam.backup_role_arn
  db_instance_arn          = module.database.db_instance_arn
  backup_schedule           = var.backup_schedule
  delete_after_days         = var.backup_delete_after_days
}
