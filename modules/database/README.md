# database

RDS MySQL（Multi-AZ、マネージドパスワード、保存時暗号化）を作成する。destroy時は常に最終スナップショットを残す。

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
| [aws_db_instance.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_parameter_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_subnet_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allocated_storage"></a> [allocated\_storage](#input\_allocated\_storage) | Allocated storage in GiB | `number` | `20` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Automated backup retention period in days | `number` | `7` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Initial database name | `string` | `"appdb"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Enable RDS deletion protection. If true, terraform destroy will fail until this is turned back off. | `bool` | `false` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | MySQL major version (minor is auto-selected) | `string` | `"8.0"` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | RDS instance class | `string` | `"db.t3.micro"` | no |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | Master username (avoid the reserved word 'admin') | `string` | `"dbadmin"` | no |
| <a name="input_multi_az"></a> [multi\_az](#input\_multi\_az) | Enable Multi-AZ. Set false to reduce cost during learning/testing. | `bool` | `true` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Prefix used for resource names | `string` | n/a | yes |
| <a name="input_protected_subnet_ids"></a> [protected\_subnet\_ids](#input\_protected\_subnet\_ids) | Protected subnet IDs (a, b) for the DB subnet group | `list(string)` | n/a | yes |
| <a name="input_rds_security_group_id"></a> [rds\_security\_group\_id](#input\_rds\_security\_group\_id) | Security group ID for the RDS instance | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_db_endpoint_address"></a> [db\_endpoint\_address](#output\_db\_endpoint\_address) | RDS endpoint address |
| <a name="output_db_endpoint_port"></a> [db\_endpoint\_port](#output\_db\_endpoint\_port) | RDS endpoint port |
| <a name="output_db_instance_arn"></a> [db\_instance\_arn](#output\_db\_instance\_arn) | ARN of the RDS DB instance |
| <a name="output_db_instance_identifier"></a> [db\_instance\_identifier](#output\_db\_instance\_identifier) | RDS DB instance identifier (used by CloudWatch alarm dimensions and AWS Backup selection) |
| <a name="output_db_name"></a> [db\_name](#output\_db\_name) | Initial database name |
| <a name="output_db_secret_arn"></a> [db\_secret\_arn](#output\_db\_secret\_arn) | ARN of the RDS-managed master user secret in Secrets Manager |
<!-- END_TF_DOCS -->
