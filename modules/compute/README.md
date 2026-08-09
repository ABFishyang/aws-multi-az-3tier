# compute

Web/App用EC2インスタンスをfor_eachで2台（AZごと）作成する。IMDSv2強制、DBパスワードはSecrets Manager経由で実行時取得。

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
| [aws_instance.web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_ssm_parameter.al2023_ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ec2_security_group_id"></a> [ec2\_security\_group\_id](#input\_ec2\_security\_group\_id) | Security group ID for the Web/App EC2 instances | `string` | n/a | yes |
| <a name="input_enable_detailed_monitoring"></a> [enable\_detailed\_monitoring](#input\_enable\_detailed\_monitoring) | Enable EC2 one-minute detailed monitoring | `bool` | `false` | no |
| <a name="input_iam_instance_profile_name"></a> [iam\_instance\_profile\_name](#input\_iam\_instance\_profile\_name) | Name of the IAM instance profile | `string` | n/a | yes |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type | `string` | `"t3.micro"` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Map of private subnet IDs (a, b) | `map(string)` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Prefix used for resource names | `string` | n/a | yes |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Root volume size in GiB | `number` | `8` | no |
| <a name="input_user_data"></a> [user\_data](#input\_user\_data) | Rendered bootstrap script (plain text; this module base64-encodes it) | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instance_ids"></a> [instance\_ids](#output\_instance\_ids) | Map of Web/App EC2 instance IDs (a, b) |
<!-- END_TF_DOCS -->
