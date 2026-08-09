# backup

AWS Backupボールト・プラン（cronスケジュール必須）・タグ+ARNベースのセレクションを作成する。

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
| [aws_backup_plan.daily](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan) | resource |
| [aws_backup_selection.tagged](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection) | resource |
| [aws_backup_vault.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_backup_role_arn"></a> [backup\_role\_arn](#input\_backup\_role\_arn) | ARN of the AWS Backup service role (from the iam module) | `string` | n/a | yes |
| <a name="input_backup_schedule"></a> [backup\_schedule](#input\_backup\_schedule) | AWS Backup cron schedule expression. No default on purpose — omitting ScheduleExpression is the exact silent-failure bug found when reviewing the reference CloudFormation series (plan/rule are created but backups never run). | `string` | n/a | yes |
| <a name="input_db_instance_arn"></a> [db\_instance\_arn](#input\_db\_instance\_arn) | ARN of the RDS DB instance to include in the backup selection | `string` | n/a | yes |
| <a name="input_delete_after_days"></a> [delete\_after\_days](#input\_delete\_after\_days) | Recovery point retention in days (RPO 24h / RTO 1 day requirement) | `number` | `30` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Prefix used for resource names | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backup_plan_id"></a> [backup\_plan\_id](#output\_backup\_plan\_id) | ID of the AWS Backup plan |
| <a name="output_backup_vault_name"></a> [backup\_vault\_name](#output\_backup\_vault\_name) | Name of the AWS Backup vault |
<!-- END_TF_DOCS -->
