# loadbalancer

ALB・ターゲットグループ・リスナーを作成する。証明書ARNが空ならHTTPのみ、指定されていればHTTP→HTTPSリダイレクト構成になる。

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http_forward](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_redirect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group_attachment.web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_log_prefix"></a> [alb\_log\_prefix](#input\_alb\_log\_prefix) | S3 key prefix for ALB access logs (must match the bucket policy's allowed path) | `string` | `"alb"` | no |
| <a name="input_alb_security_group_id"></a> [alb\_security\_group\_id](#input\_alb\_security\_group\_id) | Security group ID for the ALB | `string` | n/a | yes |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ACM certificate ARN. Empty string builds HTTP-only (no HTTPS listener). | `string` | `""` | no |
| <a name="input_enable_access_logs"></a> [enable\_access\_logs](#input\_enable\_access\_logs) | Enable ALB access logs to S3 | `bool` | `true` | no |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | URL path used for the target group health check (not a filesystem path) | `string` | `"/healthcheck.php"` | no |
| <a name="input_log_bucket_name"></a> [log\_bucket\_name](#input\_log\_bucket\_name) | S3 bucket name for ALB access logs (required when enable\_access\_logs is true) | `string` | `""` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Prefix used for resource names | `string` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Public subnet IDs (a, b) for the ALB | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC | `string` | n/a | yes |
| <a name="input_web_instance_ids"></a> [web\_instance\_ids](#input\_web\_instance\_ids) | Map of Web/App EC2 instance IDs to register as targets | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_arn"></a> [alb\_arn](#output\_alb\_arn) | ARN of the ALB |
| <a name="output_alb_arn_suffix"></a> [alb\_arn\_suffix](#output\_alb\_arn\_suffix) | ALB ARN suffix (e.g. app/name/id) — required for CloudWatch alarm dimensions, NOT the same as the full ARN |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the ALB |
| <a name="output_alb_zone_id"></a> [alb\_zone\_id](#output\_alb\_zone\_id) | Route 53 hosted zone ID of the ALB (for alias records) |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | ARN of the target group |
| <a name="output_target_group_arn_suffix"></a> [target\_group\_arn\_suffix](#output\_target\_group\_arn\_suffix) | Target group ARN suffix (e.g. targetgroup/name/id) — required for CloudWatch alarm dimensions |
<!-- END_TF_DOCS -->
