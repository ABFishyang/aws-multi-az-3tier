# ------------------------------------------------------------------
# 設計方針・CloudFormation版との違い
#
# CloudFormation版の 10-dns スタックは「ACM証明書」と「ALBを指す
# Route53エイリアスレコード」を同じテンプレートに同居させていた。
# そのため 09-loadbalancer（証明書ARNが要る）と 10-dns（ALBのDNS名が
# 要る）が相互依存になり、実際には
#   1. 証明書無しで 01-09 をデプロイ
#   2. 10-dns をデプロイして証明書ARNを取得
#   3. 証明書ARNを渡して 09 を再デプロイ
# という2段階デプロイが必要だった（README参照）。
#
# Terraform版ではこの循環を構造的に解消している。証明書の発行・検証
# 自体はALBを必要としないため、このモジュールは証明書の発行と検証
# だけを担当する。ALBを指すエイリアスレコードは、証明書にもALBにも
# 依存する「最後の一手」として、ルートの main.tf に置いている
# （dns→loadbalancer→alias という一方向の依存関係になり、
# 循環しない）。これにより `terraform apply` 一回で完結する。
# ------------------------------------------------------------------

resource "aws_acm_certificate" "main" {
  count = var.domain_name != "" ? 1 : 0

  domain_name        = var.domain_name
  validation_method   = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-cert" }
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.domain_name != "" ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type    = dvo.resource_record_type
      record  = dvo.resource_record_value
    }
  } : {}

  zone_id  = var.hosted_zone_id
  name      = each.value.name
  type      = each.value.type
  records   = [each.value.record]
  ttl       = 60
}

resource "aws_acm_certificate_validation" "main" {
  count = var.domain_name != "" ? 1 : 0

  certificate_arn          = aws_acm_certificate.main[0].arn
  validation_record_fqdns  = [for r in aws_route53_record.cert_validation : r.fqdn]
}
