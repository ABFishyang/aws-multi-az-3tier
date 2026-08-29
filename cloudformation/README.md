# CloudFormation 版

Terraform 版と同じマルチAZ 3層Web基盤を、12個の CloudFormation スタックで表現した実装です。各スタックは `Outputs` の `Export` と `Fn::ImportValue` で接続され、リソースIDを手作業で転記せずに依存関係を解決します。

> 検証範囲は `cfn-lint` による静的解析までです。実AWS環境へのデプロイは未実施であり、実行すると NAT Gateway、Interface VPC Endpoint、RDS、EC2、ALB などの料金が発生します。

## Terraform 版との対応

| CloudFormation スタック | Terraform モジュール | 主なリソース |
|---|---|---|
| `01-network` | `network` | VPC / Subnet×6 / NAT Gateway×2 / Route Table / NACL |
| `02-securitygroup` | `security` | ALB / EC2 / RDS / EFS / VPC Endpoint用SG |
| `03-iam` | `iam` | EC2・AWS Backupロール |
| `04-endpoint` | `endpoints` | SSM Interface×3 / S3 Gateway Endpoint |
| `05-logging` | `logging` | S3 / VPC Flow Logs |
| `06-storage` | `storage` | EFS / Mount Target×2 |
| `07-database` | `database` | RDS MySQL / DB Subnet Group |
| `08-compute` | `compute` | Web/App EC2×2 |
| `09-loadbalancer` | `loadbalancer` | ALB / Target Group / Listener |
| `10-dns` | `dns` + Route 53 alias | ACM証明書 / DNS検証 / Alias Record（任意） |
| `11-monitoring` | `monitoring` | SNS / CloudWatch Alarm / EventBridge |
| `12-backup` | `backup` | Backup Vault / Plan / Selection |

## 前提条件

- AWS CLI v2
- Bash（Windowsでは Git Bash または WSL）
- 構築対象サービスを操作できるAWS権限
- 通知先メールアドレス

認証情報はファイルへ書かず、AWS CLI のプロファイルまたは環境変数で設定してください。

## HTTP構成を一括デプロイ

```bash
export PROJECT=myapp
export REGION=ap-northeast-1
export EMAIL=you@example.com

bash cloudformation/scripts/deploy.sh
```

特定範囲だけを実行する場合は、スタック番号を指定します。

```bash
bash cloudformation/scripts/deploy.sh 05
bash cloudformation/scripts/deploy.sh 05 09
```

`11-monitoring` の作成後、SNSから届く購読確認メールのリンクを承認してください。

## 独自ドメインとHTTPSを使う場合

CloudFormation のクロススタック参照を一方向に保つため、HTTPSは次の順序で構成します。

1. `09-loadbalancer` をHTTPで作成
2. `10-dns` でACM証明書、DNS検証、ALB Alias Recordを作成
3. `10-dns` の証明書ARNを使って `09-loadbalancer` を更新

スクリプトでは `DOMAIN_NAME` と `HOSTED_ZONE_ID` を指定すると、この2段階更新を自動で行います。

```bash
export PROJECT=myapp
export REGION=ap-northeast-1
export EMAIL=you@example.com
export DOMAIN_NAME=app.example.com
export HOSTED_ZONE_ID=Z0000000000000000000

bash cloudformation/scripts/deploy.sh
```

対象ドメインのパブリックホストゾーンが Route 53 に存在し、ネームサーバーが正しく委任されている必要があります。証明書のDNS検証中はスタック作成が待機します。

既存のACM証明書を使う場合は `CERT_ARN` を指定できます。この場合、`10-dns` は作成しません。

```bash
export CERT_ARN=arn:aws:acm:ap-northeast-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
bash cloudformation/scripts/deploy.sh
```

## 静的解析

```bash
python -m pip install cfn-lint
cfn-lint cloudformation/templates/*.yaml
```

GitHub Actions の `CloudFormation checks` でも、全テンプレートの `cfn-lint` と全角スペース混入チェックを実行します。

## 動作確認

```bash
aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "$PROJECT-09-loadbalancer" \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" \
  --output text

aws ssm start-session --region "$REGION" --target <instance-id>
```

## 削除

```bash
bash cloudformation/scripts/destroy.sh
```

ログ用S3バケットとAWS Backupボールトには `DeletionPolicy: Retain` を設定しているため、スタック削除後も残ります。保持が不要な場合は、内容と復旧要否を確認してから個別に削除してください。

## ディレクトリ構成

```text
cloudformation/
├── README.md
├── parameters/
│   └── example.json
├── scripts/
│   ├── deploy.sh
│   └── destroy.sh
└── templates/
    ├── 01-network.yaml
    ├── 02-securitygroup.yaml
    ├── 03-iam.yaml
    ├── 04-endpoint.yaml
    ├── 05-logging.yaml
    ├── 06-storage.yaml
    ├── 07-database.yaml
    ├── 08-compute.yaml
    ├── 09-loadbalancer.yaml
    ├── 10-dns.yaml
    ├── 11-monitoring.yaml
    └── 12-backup.yaml
```
