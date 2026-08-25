# AWS マルチAZ 3層Webアーキテクチャ基盤（Terraform 版）

AWS 上にマルチAZ構成の3層Webアーキテクチャを Terraform で構築した個人学習プロジェクトです。可用性・セキュリティ・運用監視・バックアップまでを含む構成を、12モジュールで実装しています。

このリポジトリでは、以前 CloudFormation で実装していた同一アーキテクチャを Terraform で再構築しました。CloudFormation 版は [Git履歴（旧版）](https://github.com/ABFishyang/aws-multi-az-3tier/tree/9982b291471f4a8efdeef565ae11d0031c7fbd30) から確認できます。**同一構成を2つのIaCツールで実装して比較検証すること自体が本プロジェクトの目的の一つ**であり、両者の設計上の違いは後述の「CloudFormation版との違い」にまとめています。

---

## 構成図

```text
VPC 10.0.0.0/16
├── ap-northeast-1a
│   ├── public-a     10.0.0.0/24   (ALB, NAT Gateway A)
│   ├── private-a    10.0.10.0/24  (Web/App EC2 A)
│   └── protected-a  10.0.20.0/24  (RDS, EFS mount target A) ※デフォルトルート無し
└── ap-northeast-1c
    ├── public-b     10.0.1.0/24   (ALB, NAT Gateway B)
    ├── private-b    10.0.11.0/24  (Web/App EC2 B)
    └── protected-b  10.0.21.0/24  (RDS, EFS mount target B) ※デフォルトルート無し
```

- Public: ALBとNATゲートウェイのみ。EC2は置かない
- Private: Web/App EC2。NAT経由でアウトバウンド
- Protected: RDS・EFS。デフォルトルートを持たず、VPC内部通信のみ
- 踏み台サーバーレス（Session Manager + Interface VPCエンドポイント）

---

## モジュール構成（CloudFormationスタックとの対応）

| # | モジュール | 対応するCFNスタック | 主なリソース | 依存 |
|---|---|---|---|---|
| 01 | `network` | 01-network | VPC / IGW / Subnet×6 / NATGW×2 / RouteTable×4 / NACL×3 | — |
| 02 | `security` | 02-securitygroup | SecurityGroup×5（ALB / EC2 / RDS / EFS / VPCE） | network |
| 03 | `iam` | 03-iam | EC2ロール / インスタンスプロファイル / AWS Backupロール | — |
| 04 | `endpoints` | 04-endpoint | SSM Interfaceエンドポイント×3 / S3 Gatewayエンドポイント | network, security |
| 05 | `logging` | 05-logging | ログ用S3バケット / バケットポリシー / VPCフローログ | network |
| 06 | `storage` | 06-storage | EFS / マウントターゲット×2 | network, security |
| 07 | `database` | 07-database | DBサブネットグループ / パラメータグループ / RDS MySQL | network, security |
| 08 | `compute` | 08-compute | EC2×2（Web/App） | network, security, iam, storage, database |
| 09 | `dns` | 10-dns（一部） | ACM証明書 / DNS検証（**ALBに依存しない**） | — |
| 09 | `loadbalancer` | 09-loadbalancer | ALB / ターゲットグループ / リスナー | network, security, compute, dns, logging |
| — | `aws_route53_record.alias`（ルート直書き） | 10-dns（一部） | ALBを指すエイリアスレコード | dns, loadbalancer |
| 11 | `monitoring` | 11-monitoring | SNS / TopicPolicy / CloudWatchアラーム×6 / EventBridge | compute, database, loadbalancer |
| 12 | `backup` | 12-backup | Backupボールト / プラン / セレクション | iam, database |

Terraformは単一の依存グラフで解決するため、CloudFormation版にあった「05-loggingを09-loadbalancerより先にデプロイする」といったスタック順序の制約は、モジュール間の暗黙・明示の依存関係として自動的に表現される。`terraform apply` は基本的に1回で完結する。

---

## CloudFormation版との違い

### 1. カスタムドメインの循環依存を構造的に解消

CloudFormation版は、09-loadbalancer（証明書ARNが要る）と10-dns（ALBのDNS名が要る）が相互依存になり、

1. 証明書無しで 01〜09 をデプロイ
2. 10-dns をデプロイして証明書ARNを取得
3. 証明書ARNを渡して 09 を再デプロイ

という2段階デプロイが必要だった。

Terraform版では `dns` モジュールを「証明書の発行・検証のみ」に絞り、ALBへの依存を一切持たせていない。ALBを指すRoute53エイリアスレコードは、証明書とALB両方に依存する最後の1リソースとしてルートの `main.tf` に直書きしている。これにより `dns → loadbalancer → alias` という一方向の依存関係になり、`terraform apply` 一回で完結する。

（`dns`モジュールと`loadbalancer`モジュールを相互参照させる素朴な実装だと、Terraformの依存グラフが真に循環し `Error: Cycle` でplanが失敗する。これは「単一のapplyで解決する」というTerraformの性質だけでは自動的に解けない問題で、モジュール境界の切り方そのものを変える必要があった。）

### 2. セキュリティグループの既定挙動の違い

CloudFormation版はRDS/EFS/VPCエンドポイント用のSGに「アウトバウンド不要」を表現するため、`127.0.0.1/32` へのダミーegressルールを明示的に追加していた（`SecurityGroupEgress`を空リストにする代替手段）。

Terraformの `aws_security_group` は、inlineの `ingress`/`egress` ブロックを一切書かない場合でも、AWSが新規SG作成時に自動付与する「全許可アウトバウンド」ルールを既定で除去する。そのためTerraform版ではダミールールが不要で、単純に何も書かないだけで意図した「アウトバウンド不要」が実現できる。

### 3. EC2 2台構成の重複排除

CloudFormation版は素のYAMLでは2台分をほぼ手書きコピーする必要があり、後から `Fn::ForEach`（`AWS::LanguageExtensions`）で重複を解消した。Terraform版は最初から `for_each` で1つのリソース定義から2台を生成しており、この種の重複が構造的に発生しない。

### 4. RDS削除時の挙動

CloudFormation版の `DeletionPolicy: Snapshot` に相当する設定として、`skip_final_snapshot = false` を明示している。`deletion_protection`（destroy自体を拒否する設定）とは独立した設定であることに注意（両者を混同すると、意図せず最終スナップショットを残さずに削除してしまう設計ミスになりうる）。

---

## 設計上の判断と、その理由

### 踏み台サーバーを置かず、Session Manager でアクセスする

Interface VPCエンドポイント（`ssm` / `ssmmessages` / `ec2messages`）経由でSession Managerを利用する。インバウンドポートを一切開放せず、EC2を完全にプライベートサブネットに閉じたまま運用できる。3つのエンドポイントは1つでも欠けるとセッションが確立できない。

### サブネットを3階層に分け、Protected にはデフォルトルートを置かない

RDSとEFSはマネージドサービスで外部通信が不要なため、NATへの経路は攻撃面を増やすだけになる。VPC内の通信は自動生成されるlocalルートで完結する。

### NATゲートウェイをAZごとに配置する

Privateサブネットのルートテーブルを1つにまとめると片方のNATにしか経路を向けられず、AZ障害時にもう一方のAZまで巻き込まれる。学習目的で費用を抑える場合は1台に減らせるが、可用性が下がることに注意。

### RDSのパスワードをどこにも書かない

`manage_master_user_password = true` により、RDSがSecrets Managerにシークレットを自動生成・ローテーション管理する。Terraformコード・tfstate・Gitのいずれにも平文パスワードは現れない（tfstateにはSecrets ManagerのARNのみが記録される）。

### IMDSv2 を強制する

`http_tokens = "required"` を指定。UserDataはIMDSから読み取れるため、IMDSv1が有効な状態でアプリケーションにSSRF脆弱性があるとUserData内の情報が外部から取得できてしまう。

### セキュリティグループはIPではなくSGを参照させる

`referenced_security_group_id` でSG同士を連鎖させる（Internet → ALB → EC2 → RDS / EFS / VPCE）。IPアドレスが変わっても設定を追従させる必要がなくなる。ステートフルなので戻り方向のルールは作成していない。

### IAMロールのEFS権限を最小化

`elasticfilesystem:ClientRootAccess`（UID/GID強制を素通りする権限）は付与せず、`ClientMount`/`ClientWrite`のみに限定。Resourceもアカウント/リージョン内のEFSに限定している。

---

## 参考にした記事

本プロジェクトのアーキテクチャは、[CloudFormation旧版](https://github.com/ABFishyang/aws-multi-az-3tier/tree/9982b291471f4a8efdeef565ae11d0031c7fbd30) と同一の設計を踏襲している。CloudFormation版の実装にあたって参考にした記事や、そこで見つかった問題点の詳細は、旧版の [`docs/code-review.md`](https://github.com/ABFishyang/aws-multi-az-3tier/blob/9982b291471f4a8efdeef565ae11d0031c7fbd30/docs/code-review.md) を参照。

---

## デプロイ手順

### 前提条件

- Terraform 1.10 以降
- AWS CLI v2（`aws sts get-caller-identity` で現在のIDを確認しておく）
- 構築対象リソースの作成に必要なAWS操作権限

### 設定

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集し、少なくとも `notification_email` を設定する。独自ドメインを使う場合は `domain_name` と `hosted_zone_id` も設定する（両方空文字列のままならALBのDNS名 + HTTPのみで構築される）。

### 実行

```bash
make init
make validate
make plan
make apply
```

`make` が無い場合は `terraform init` / `terraform validate` / `terraform plan -out=tfplan` / `terraform apply tfplan` を直接実行する。

デプロイ後、SNSから届く購読確認メールのリンクをクリックしないと通知は届かない。

### 動作確認

```bash
terraform output site_url
terraform output alb_dns_name

# Session Manager で EC2 に接続（キーペア不要）
aws ssm start-session --region ap-northeast-1 --target <instance-id>
```

### 削除

```bash
make destroy
```

ログ用S3バケットとBackupボールトには `prevent_destroy = true` を設定しているため、`terraform destroy` はこれらのリソースで失敗する（意図的な安全装置）。本当に削除する場合は、該当する `lifecycle` ブロックを一旦コメントアウトしてから再実行すること。

---

## 費用の目安（東京リージョン、概算・月額）

同一アーキテクチャのため、CloudFormation版と同水準。

| リソース | 月額 |
|---|---|
| NATゲートウェイ × 2 | 約 $70 |
| Interface VPCエンドポイント × 3 | 約 $21 |
| RDS db.t3.micro Multi-AZ | 約 $30 |
| EC2 t3.micro × 2 | 約 $17 |
| ALB | 約 $18 |
| EFS / S3 / CloudWatch | 数ドル |
| **合計** | **約 $160 前後** |

費用を抑える場合は `terraform.tfvars` で `db_multi_az = false`（約$15削減）などを調整する。動作確認が終わり次第 `make destroy` で削除すること。

---

## Linting & documentation

[tflint](https://github.com/terraform-linters/tflint)（`aws` ruleset）と [terraform-docs](https://github.com/terraform-docs/terraform-docs) を使用。CI（`.github/workflows/terraform.yml`）で `validate` / `lint` / `docs`（ドキュメント同期チェック）の3ジョブが自動実行される。

```bash
make lint-init   # 初回のみ：.tflint.hcl のプラグインをダウンロード
make lint        # 静的解析
make docs        # modules/*/README.md とこのファイルの表を再生成
```

**Windows note:** vanilla Git Bash doesn't ship `make`. Install it (`choco install make` / `scoop install make`), or run the underlying `tflint` / `terraform-docs` commands directly.

---

## ディレクトリ構成

```text
.
├── main.tf
├── outputs.tf
├── providers.tf
├── variables.tf
├── versions.tf
├── terraform.tfvars.example
├── Makefile
├── .tflint.hcl
├── .terraform-docs.yml
├── .terraform-docs-root.yml
├── modules
│   ├── network      (README.md 付き)
│   ├── security     (README.md 付き)
│   ├── iam          (README.md 付き)
│   ├── endpoints    (README.md 付き)
│   ├── logging      (README.md 付き)
│   ├── storage      (README.md 付き)
│   ├── database     (README.md 付き)
│   ├── compute      (README.md 付き)
│   ├── loadbalancer (README.md 付き)
│   ├── dns          (README.md 付き)
│   ├── monitoring   (README.md 付き)
│   └── backup       (README.md 付き)
└── user_data
    └── web-server.sh.tftpl
```

---

## 使用技術

- **IaC**: Terraform（HCL）、AWS provider ~> 6.0
- **静的解析**: tflint + tflint-ruleset-aws
- **ドキュメント生成**: terraform-docs
- **CI**: GitHub Actions（validate / lint / docs の3ジョブ）

---

## 今後の課題

- Auto Scaling Group の導入によるスケーラビリティの確保（現在はEC2を静的に2台配置）
- リモートバックエンド（S3 + DynamoDBロック）の導入。現在はローカルstate前提
- WAF の導入によるアプリケーション層の防御
- `terraform plan` の実機検証（このリポジトリは `tflint` による静的解析と、モジュール間の変数配線をスクリプトで突き合わせる手作業チェックまでは実施済みだが、実際の `terraform apply` による検証はまだ行っていない）

---

## 注意事項

本リポジトリは学習目的で作成した個人プロジェクトです。実際にAWS上へデプロイすると課金が発生します（上記費用の目安を参照）。認証情報・アカウントID・実IPアドレス等の機密情報は含まれていません。

---

## Reference

各モジュールの詳細な入出力は `modules/<name>/README.md` を参照（`terraform-docs` で自動生成、`make docs` で更新可能）。

ルートモジュールの入出力一覧:

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.61.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_backup"></a> [backup](#module\_backup) | ./modules/backup | n/a |
| <a name="module_compute"></a> [compute](#module\_compute) | ./modules/compute | n/a |
| <a name="module_database"></a> [database](#module\_database) | ./modules/database | n/a |
| <a name="module_dns"></a> [dns](#module\_dns) | ./modules/dns | n/a |
| <a name="module_endpoints"></a> [endpoints](#module\_endpoints) | ./modules/endpoints | n/a |
| <a name="module_iam"></a> [iam](#module\_iam) | ./modules/iam | n/a |
| <a name="module_loadbalancer"></a> [loadbalancer](#module\_loadbalancer) | ./modules/loadbalancer | n/a |
| <a name="module_logging"></a> [logging](#module\_logging) | ./modules/logging | n/a |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | ./modules/monitoring | n/a |
| <a name="module_network"></a> [network](#module\_network) | ./modules/network | n/a |
| <a name="module_security"></a> [security](#module\_security) | ./modules/security | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ./modules/storage | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_route53_record.alias](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_log_prefix"></a> [alb\_log\_prefix](#input\_alb\_log\_prefix) | S3 key prefix for ALB access logs (no trailing slash) | `string` | `"alb"` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Two availability zones. Some accounts cannot use 1b in ap-northeast-1, hence the 1a/1c default. | `list(string)` | <pre>[<br/>  "ap-northeast-1a",<br/>  "ap-northeast-1c"<br/>]</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region used by this project | `string` | `"ap-northeast-1"` | no |
| <a name="input_backup_delete_after_days"></a> [backup\_delete\_after\_days](#input\_backup\_delete\_after\_days) | Recovery point retention in days | `number` | `30` | no |
| <a name="input_backup_schedule"></a> [backup\_schedule](#input\_backup\_schedule) | AWS Backup cron schedule expression. Default: daily at 16:00 UTC (01:00 JST). | `string` | `"cron(0 16 ? * * *)"` | no |
| <a name="input_cpu_alarm_threshold"></a> [cpu\_alarm\_threshold](#input\_cpu\_alarm\_threshold) | CPU utilization alarm threshold in percent (EC2 and RDS) | `number` | `80` | no |
| <a name="input_db_allocated_storage"></a> [db\_allocated\_storage](#input\_db\_allocated\_storage) | Allocated storage in GiB | `number` | `20` | no |
| <a name="input_db_backup_retention_period"></a> [db\_backup\_retention\_period](#input\_db\_backup\_retention\_period) | Automated backup retention period in days | `number` | `7` | no |
| <a name="input_db_deletion_protection"></a> [db\_deletion\_protection](#input\_db\_deletion\_protection) | Enable RDS deletion protection. If true, terraform destroy will fail until this is turned back off. | `bool` | `false` | no |
| <a name="input_db_engine_version"></a> [db\_engine\_version](#input\_db\_engine\_version) | MySQL major version (minor is auto-selected; avoids pinning to an EOL minor version) | `string` | `"8.0"` | no |
| <a name="input_db_instance_class"></a> [db\_instance\_class](#input\_db\_instance\_class) | RDS instance class | `string` | `"db.t3.micro"` | no |
| <a name="input_db_master_username"></a> [db\_master\_username](#input\_db\_master\_username) | Master username (avoid the reserved word 'admin') | `string` | `"dbadmin"` | no |
| <a name="input_db_multi_az"></a> [db\_multi\_az](#input\_db\_multi\_az) | Enable RDS Multi-AZ. Set false to cut cost while testing (~$15/month). | `bool` | `true` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Initial database name | `string` | `"appdb"` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Custom domain name for the ALB (e.g. app.example.com). Leave empty to build HTTP-only using the ALB's own DNS name — no certificate or Route 53 record is created. | `string` | `""` | no |
| <a name="input_efs_performance_mode"></a> [efs\_performance\_mode](#input\_efs\_performance\_mode) | EFS performance mode | `string` | `"generalPurpose"` | no |
| <a name="input_efs_throughput_mode"></a> [efs\_throughput\_mode](#input\_efs\_throughput\_mode) | EFS throughput mode | `string` | `"bursting"` | no |
| <a name="input_enable_access_logs"></a> [enable\_access\_logs](#input\_enable\_access\_logs) | Enable ALB access logs to S3 | `bool` | `true` | no |
| <a name="input_enable_detailed_monitoring"></a> [enable\_detailed\_monitoring](#input\_enable\_detailed\_monitoring) | Enable EC2 one-minute detailed monitoring (incurs a small charge) | `bool` | `false` | no |
| <a name="input_flow_log_prefix"></a> [flow\_log\_prefix](#input\_flow\_log\_prefix) | S3 key prefix for VPC flow logs (no trailing slash) | `string` | `"vpcflowlogs"` | no |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | URL path used for the ALB target group health check (not a filesystem path) | `string` | `"/healthcheck.php"` | no |
| <a name="input_hosted_zone_id"></a> [hosted\_zone\_id](#input\_hosted\_zone\_id) | Existing Route 53 hosted zone ID. Required when domain\_name is set (enforced by the check block at the bottom of this file). | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for the Web/App servers | `string` | `"t3.micro"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Number of days to retain ALB/flow logs before expiration | `number` | `90` | no |
| <a name="input_notification_email"></a> [notification\_email](#input\_notification\_email) | Email address subscribed to the SNS alert topic (a confirmation email will be sent after apply) | `string` | n/a | yes |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | CIDRs of private-a and private-b (Web/App EC2) | `list(string)` | <pre>[<br/>  "10.0.10.0/24",<br/>  "10.0.11.0/24"<br/>]</pre> | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Prefix used for resource names, tags, and the S3 log bucket name | `string` | `"myapp"` | no |
| <a name="input_protected_subnet_cidrs"></a> [protected\_subnet\_cidrs](#input\_protected\_subnet\_cidrs) | CIDRs of protected-a and protected-b (RDS / EFS, no default route) | `list(string)` | <pre>[<br/>  "10.0.20.0/24",<br/>  "10.0.21.0/24"<br/>]</pre> | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | CIDRs of public-a and public-b (ALB / NAT Gateway) | `list(string)` | <pre>[<br/>  "10.0.0.0/24",<br/>  "10.0.1.0/24"<br/>]</pre> | no |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Root volume size in GiB | `number` | `8` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | IPv4 CIDR of the VPC | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the ALB |
| <a name="output_alert_topic_arn"></a> [alert\_topic\_arn](#output\_alert\_topic\_arn) | ARN of the SNS alert topic |
| <a name="output_backup_vault_name"></a> [backup\_vault\_name](#output\_backup\_vault\_name) | Name of the AWS Backup vault |
| <a name="output_db_endpoint_address"></a> [db\_endpoint\_address](#output\_db\_endpoint\_address) | RDS endpoint address |
| <a name="output_db_secret_arn"></a> [db\_secret\_arn](#output\_db\_secret\_arn) | ARN of the RDS-managed master user secret in Secrets Manager |
| <a name="output_log_bucket_name"></a> [log\_bucket\_name](#output\_log\_bucket\_name) | S3 bucket name for ALB access logs and VPC flow logs |
| <a name="output_site_url"></a> [site\_url](#output\_site\_url) | URL to reach the application (HTTPS custom domain if configured, otherwise the ALB DNS name over HTTP) |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC |
| <a name="output_web_instance_ids"></a> [web\_instance\_ids](#output\_web\_instance\_ids) | Map of Web/App EC2 instance IDs (a, b) |
<!-- END_TF_DOCS -->

## License

MIT License. See [LICENSE](LICENSE).
