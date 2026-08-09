# ------------------------------------------------------------------
# 設計方針
# 1. HealthCheckPath は URL パス（/healthcheck.php）を指定する。
# 2. ssl_policy を明示する。既定の ELBSecurityPolicy-2016-08 は
#    TLS1.0/1.1 を許容するため、TLS13-1-2 プロファイルを指定する。
# 3. アクセスログのバケットポリシーへの依存を明示する（下の
#    depends_on）。CloudFormation版はこれをスタックのデプロイ順序
#    （05-logging を 09-loadbalancer より先に）で担保していたが、
#    Terraformでは同一apply内でリソース間の依存として直接表現できる。
# 4. certificate_arn が空文字列ならHTTPのみで構築する（証明書無しでも
#    動作確認できる）。空でなければHTTP→HTTPSリダイレクト + HTTPS
#    リスナーを作る。
# ------------------------------------------------------------------

locals {
  has_certificate = var.certificate_arn != ""
}

resource "aws_lb" "main" {
  name                = "${var.project_name}-alb"
  load_balancer_type  = "application"
  internal            = false
  ip_address_type     = "ipv4"
  subnets             = var.public_subnet_ids
  security_groups     = [var.alb_security_group_id]

  idle_timeout                     = 60
  drop_invalid_header_fields       = true

  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      enabled  = true
      bucket    = var.log_bucket_name
      prefix    = var.alb_log_prefix
    }
  }

  # 注意: 「バケットポリシーが先に存在しないとALB作成が失敗する」という
  # 依存関係は、このモジュール内の変数だけでは表現できない
  # （depends_on はリソース参照が必要で、渡された文字列値では効かない）。
  # 呼び出し側（ルートの main.tf）で
  #   module "loadbalancer" { ... depends_on = [module.logging] ... }
  # として、logging モジュール全体（バケットポリシーを含む）の完了を
  # 待ってからこのモジュールを評価するようにしている。

  tags = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-tg-web"
  vpc_id      = var.vpc_id
  protocol     = "HTTP"
  port         = 80
  target_type  = "instance"

  health_check {
    enabled             = true
    protocol             = "HTTP"
    path                  = var.health_check_path
    interval              = 30
    timeout                = 5
    healthy_threshold      = 2
    unhealthy_threshold    = 3
    matcher                = "200"
  }

  deregistration_delay = 30
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  tags = { Name = "${var.project_name}-tg-web" }
}

resource "aws_lb_target_group_attachment" "web" {
  for_each = var.web_instance_ids

  target_group_arn = aws_lb_target_group.web.arn
  target_id         = each.value
  port               = 80
}

# 証明書がある場合: HTTP は HTTPS へリダイレクト
resource "aws_lb_listener" "http_redirect" {
  count = local.has_certificate ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  protocol            = "HTTP"
  port                 = 80

  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port         = "443"
      host         = "#{host}"
      path         = "/#{path}"
      query        = "#{query}"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.has_certificate ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  protocol            = "HTTPS"
  port                 = 443
  ssl_policy           = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn      = var.certificate_arn

  default_action {
    type              = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# 証明書が無い場合: HTTP をそのままターゲットへ転送
resource "aws_lb_listener" "http_forward" {
  count = local.has_certificate ? 0 : 1

  load_balancer_arn = aws_lb.main.arn
  protocol            = "HTTP"
  port                 = 80

  default_action {
    type              = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
