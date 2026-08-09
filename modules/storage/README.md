# storage

保存時暗号化・転送時TLS強制・ライフサイクルポリシー付きのEFSファイルシステムとマウントターゲット x2AZ を作成する。

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
| [aws_efs_backup_policy.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_backup_policy) | resource |
| [aws_efs_file_system.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_file_system_policy.enforce_tls](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system_policy) | resource |
| [aws_efs_mount_target.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_efs_security_group_id"></a> [efs\_security\_group\_id](#input\_efs\_security\_group\_id) | Security group ID for the EFS mount targets | `string` | n/a | yes |
| <a name="input_performance_mode"></a> [performance\_mode](#input\_performance\_mode) | EFS performance mode | `string` | `"generalPurpose"` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Prefix used for resource names | `string` | n/a | yes |
| <a name="input_protected_subnet_ids"></a> [protected\_subnet\_ids](#input\_protected\_subnet\_ids) | Map of protected subnet IDs (a, b) to place EFS mount targets in | `map(string)` | n/a | yes |
| <a name="input_throughput_mode"></a> [throughput\_mode](#input\_throughput\_mode) | EFS throughput mode | `string` | `"bursting"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_file_system_id"></a> [file\_system\_id](#output\_file\_system\_id) | ID of the EFS file system |
<!-- END_TF_DOCS -->
