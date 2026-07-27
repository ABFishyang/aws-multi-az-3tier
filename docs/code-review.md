# cloud5.jp「AWSマルチAZ3層アーキテクチャの構築」CloudFormation連載 コードレビュー報告書

- 対象: 協栄情報ブログ（cloud5.jp）全15記事シリーズ / 著者 suzuki-n / 公開 2024年7月
- レビュー実施日: 2026年7月27日
- レビュー範囲（本報告書）: 概要 / VPC / セキュリティグループ / IAMロール / RDS / Backup / Health・EventBridge / CloudWatch・SNS の8記事
- 未レビュー（次回対応）: キーペア / EFS / SSM / EC2 / Route53 / ACM / ALB / S3・VPC Flow Logs・ALB access log の7記事

---

## 1. 総評

アーキテクチャの設計思想そのものは妥当で、3層分離・マルチAZ・Session Manager によるサーバーレス踏み台・ログのS3集約・AWS Backup による日次取得といった構成は、実務でも通用する標準的な形をしている。**アーキテクチャは参考にする価値がある。**

一方でテンプレートの実装品質には重大な問題が多数あり、**そのままコピーしても動作しない、あるいはデプロイは成功するのに機能しない（サイレント障害）ケースが複数存在する。**

検出した問題を深刻度別に分類すると以下のとおり。

| 深刻度 | 件数 | 内容 |
|---|---|---|
| 致命（デプロイ不能 / 機能不全） | 9件 | 未定義パラメータ参照、重複キー、ScheduleExpression欠落、TopicPolicy欠落 など |
| 重大（セキュリティ） | 4件 | 認証情報の平文記載、RDSのSG全開放、実リソースIDの公開、暗号化未設定 |
| 構造的（再利用性） | 5件 | Export未使用、ハードコード多数、命名固定 |
| 軽微（品質・運用） | 10件超 | 型不一致、未使用パラメータ、通知ノイズ、記事内の記述矛盾 |

---

## 2. 致命的な問題

### 2-1. 【VPC】全体ソースコードの先頭が重複している

「5.全体構築ソースコード」の冒頭が次のようになっている。

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Resources:
AWSTemplateFormatVersion: '2010-09-09'   # ← 重複
Resources:                                # ← 重複
```

YAMLの重複キーであり、テンプレートとして不正。コピーした時点でパースエラーになる。

**対応**: 冒頭2行を削除する。

---

### 2-2. 【CloudWatch・SNS / Health・EventBridge】Parameters セクションが存在しないのに `!Ref` している

両テンプレートとも `Parameters:` を一切定義していないにもかかわらず、以下を参照している。

| テンプレート | 未定義のまま参照されている論理ID |
|---|---|
| Health・EventBridge | `SNSEmail` |
| CloudWatch（メトリクス） | `SNSEmail`, `InstanceId`, `ImageId`, `InstanceType`, `Device`, `FilesystemType` |
| CloudWatch（エラーログ） | `EmailAddress`, `LogGroupName`, `MetricNamespace`, `MetricName` |

CloudFormation は `Unresolved resource dependencies` を返し、**スタック作成が開始すらされない**。連載の最終盤3記事のうち2記事のテンプレートが、記載どおりでは動かない状態にある。

さらにエラーログ用テンプレートでは、解説表に `FilterPattern: !Ref FilterPattern` と書かれているが、コード側は `'?error ?Error ?ERROR'` のリテラルであり、記事内で不整合が生じている。

**対応**: 必要な `Parameters` を全て定義する。メールアドレスは `NoEcho` 不要だが `AllowedPattern` で形式検証を入れる。

---

### 2-3. 【Health・EventBridge】SNS TopicPolicy が無く、通知が届かない

EventBridge ルールのターゲットに SNS トピックを指定しているが、`AWS::SNS::TopicPolicy` で `events.amazonaws.com` に `sns:Publish` を許可していない。

この場合の挙動が問題で、**スタックは正常に作成され、コンソール上もルールとターゲットは正しく表示される。しかしイベント発生時のターゲット呼び出しが権限不足で失敗し、メールは永久に届かない。** エラーはCloudFormationにもコンソールのルール画面にも出ない。

記事の「7.確認」セクションも、コンソールでルールとターゲットとメールアドレスが表示されていることを確認しているだけで、**実際の通知到達は検証していない**。著者自身がこの欠陥に気づけていない。

**対応**:

```yaml
NotificationTopicPolicy:
  Type: AWS::SNS::TopicPolicy
  Properties:
    Topics:
      - !Ref NotificationTopic
    PolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Sid: AllowEventBridgePublish
          Effect: Allow
          Principal:
            Service: events.amazonaws.com
          Action: sns:Publish
          Resource: !Ref NotificationTopic
          Condition:
            StringEquals:
              aws:SourceAccount: !Ref AWS::AccountId
        - Sid: AllowCloudWatchAlarmPublish
          Effect: Allow
          Principal:
            Service: cloudwatch.amazonaws.com
          Action: sns:Publish
          Resource: !Ref NotificationTopic
          Condition:
            StringEquals:
              aws:SourceAccount: !Ref AWS::AccountId
```

`aws:SourceAccount` 条件は、他アカウントからの publish を防ぐために付ける（Confused Deputy 対策）。

---

### 2-4. 【Backup】ScheduleExpression が無く、バックアップが一度も実行されない

テンプレートの `Description` には次のように書かれている。

> Backup Plan template to back up specified EC2 instances **daily at 16:00 UTC**.

しかし `BackupPlanRule` に `ScheduleExpression` が存在しない。

```yaml
BackupPlanRule:
  - RuleName: "RuleForDailyBackups"
    TargetBackupVault: !Ref BackupVault
    Lifecycle:
      DeleteAfterDays: 30
    RecoveryPointTags:
      Name: "naoki-backup-ec2"
    # ScheduleExpression が無い
```

`ScheduleExpression` を省略すると、そのルールは**オンデマンド実行専用**になる。プランもルールもコンソールに表示されるため、設定できているように見えるが、日次バックアップは永久に走らない。

概要記事の要件は「RPO 最長24時間前」であり、この状態では**要件を満たしていないことに気づかないまま運用が始まる**。バックアップの不備は、必要になった瞬間まで発覚しない種類の障害であり、実務では最も損害が大きい部類に入る。

**対応**:

```yaml
ScheduleExpression: "cron(0 16 * * ? *)"
ScheduleExpressionTimezone: "Asia/Tokyo"   # タイムゾーンを明示する
StartWindowMinutes: 60
CompletionWindowMinutes: 180
```

---

### 2-5. 【Backup】参照している IAM ロールが連載中で作成されていない

```yaml
IamRoleArn: arn:aws:iam::ユーザーID:role/naoki-ec2backup
```

`naoki-ec2backup` というロールを参照しているが、**このロールを作成する記述が連載のどの記事にも無い**。IAMロール記事で作られるのは EC2 用の `naoki-role-ec2` のみ。

読者が記事どおりに進めると、ここで初めて「存在しないロール」を参照することになる。

**対応**: `AWSBackupServiceRolePolicyForBackup` と `...ForRestores` をアタッチした AWS Backup 用サービスロールを、同一テンプレート内で作成して `!GetAtt` で参照する。

---

### 2-6. 【RDS】EngineVersion 8.0.35 は現在作成できない

```yaml
Engine: mysql
EngineVersion: 8.0.35
```

MySQL 8.0.35 は標準サポートが終了しており、**新規インスタンスの作成ができない**。2024年時点の記事のため当時は有効だったが、現在そのままでは失敗する。

**対応**: 現行の LTS を確認して指定する。バージョンは時期により変わるため、テンプレートにはパラメータ化して `AllowedValues` を持たせる形が望ましい。マイナーバージョンを固定せず `8.0` のようにファミリー指定し、`AutoMinorVersionUpgrade: true` を併用する方法もある。

---

### 2-7. 【RDS】YAML中に全角スペース（U+3000）が混入している

```yaml
DBSubnetGroupDescription: "DB Subnet Group for RDS"　# 説明
DBSubnetGroupName: !Ref DBSubnetGroupName　# グループ名
SubnetIds: !Ref SubnetIds　#サブネットID
```

`"` とコメント記号 `#` の間が半角スペースではなく**全角スペース**になっている。YAMLでは全角スペースは空白文字として扱われないため、コメントが値の一部として解釈され、パースエラーまたは意図しない値になる。

日本語入力のまま空白を打つと発生する典型的な事故で、**エディタ上では見分けがつかない**のが厄介な点。VS Code は全角スペースを枠付きで表示するので、これを有効にしておくと検出できる。`cfn-lint` でも検出可能。

---

### 2-8. 【セキュリティグループ】記事内でコードが矛盾しており、片方はRDSを全世界に開放する

RDS用セキュリティグループの記述が、同じ記事の中で2箇所異なっている。

| 箇所 | 記述 |
|---|---|
| 「5.全体のソースコード」 | `SourceSecurityGroupId: !Ref NaokiSgEc2` |
| 「6-3.RDS用セキュリティグループ」 | `CidrIp: 0.0.0.0/0` |

要件には「RDSはプライベートサブネットからのみのアクセスとする」と明記されているにもかかわらず、**6-3節のコードをコピーするとポート3306が全世界に開放される**。

RDS自体は `PubliclyAccessible: false` かつプロテクトサブネット配置なのでインターネットから直接到達はしないが、SG設定としては明確な誤りであり、VPC内の全リソースからDBへ到達可能になる。多層防御の観点で許容できない。

**対応**: `SourceSecurityGroupId` で EC2 のSGを指定する（章5が正しい）。

---

### 2-9. 【セキュリティグループ】EFS のインバウンドルールが重複定義されている

「5.全体のソースコード」では、`NaokiSgEfs` のインラインで EC2→2049 を許可し、さらに別リソース `NaokiEfsIngressEc2` でも同じ EC2→2049 を許可している。

同一内容のルールを二重に作ろうとするため、デプロイ時に `InvalidPermission.Duplicate` でスタックが失敗する。

なお「6-5.EFS用のセキュリティグループの設定」では `SecurityGroupIngress: []` になっており、ここでも記事内で矛盾している。

**対応**: インラインを `[]` にして別リソース側に寄せるか、その逆か、どちらか一方に統一する。SG間で相互参照が発生する場合は別リソース方式に統一するのが安全。

---

## 3. セキュリティ上の問題

### 3-1. 【RDS】Secrets Manager に認証情報を平文で書いている

```yaml
CloudFormationCreatedSecret:
  Type: 'AWS::SecretsManager::Secret'
  Properties:
    SecretString: '{"username": "ユーザー名", "password": "パスワード"}'
```

パスワードをテンプレートに直接記述しており、**Secrets Manager を使う意味が完全に失われている**。テンプレートはGitに入り、CloudFormationのイベント履歴にも残る。

要件には「AWS Secrets Manager でパスワードを取得・管理」とあるが、実態は「手で決めたパスワードをSecrets Managerに置いただけ」になっている。

**対応（推奨順）**:

1. **RDS マネージドパスワードを使う（最も安全）**

```yaml
ManageMasterUserPassword: true
MasterUserSecretKmsKeyId: alias/aws/secretsmanager
```

RDS が自動でシークレットを生成・保管し、ローテーションまで管理する。テンプレートにパスワードは一切現れない。

2. **GenerateSecretString を使う**

```yaml
GenerateSecretString:
  SecretStringTemplate: '{"username": "dbadmin"}'
  GenerateStringKey: "password"
  PasswordLength: 32
  ExcludeCharacters: '"@/\'
```

加えて `AWS::SecretsManager::SecretTargetAttachment` を作成しないとローテーションが構成できない点にも注意。

---

### 3-2. 【RDS / Backup】実在のリソースIDとアカウント情報が公開されている

```yaml
VPCId:    Default: vpc-062d5b30de12cff6a
SubnetIds: Default: subnet-06938606508b14fa2,subnet-0ed3deb02f824b0ae
VPCSecurityGroups: - "sg-0f0fab14c0b720d0c"
```

実在のリソースIDが公開ブログにそのまま掲載されている。単体で悪用できる情報ではないが、公開すべきものではない。加えて、これらがハードコードされているため**テンプレートの再利用性がゼロ**になっている。

---

### 3-3. 【RDS】保存時暗号化が設定されていない

`StorageEncrypted` の指定が無く、デフォルトの無効のままになっている。概要記事では「転送時の暗号化の実施(HTTPS化)」に触れているが、保存時暗号化には言及がない。

**対応**: `StorageEncrypted: true` を指定する（作成後の有効化はスナップショット経由の再作成が必要になるため、最初から入れる）。

---

### 3-4. 【IAMロール】要件と実装が矛盾している（過剰権限）

要件にはこう書かれている。

> 権限はセキュリティの観点から最小限に制限する。

しかし実装は次のとおり。

```yaml
ManagedPolicyArns:
  - 'arn:aws:iam::aws:policy/CloudWatchAgentAdminPolicy'
  - 'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore'
```

`CloudWatchAgentAdminPolicy` は、CloudWatch エージェントの設定を **SSM パラメータストアへ書き込む** 権限まで含む管理者向けポリシー。メトリクスとログを送信するだけの EC2 には過剰。

**対応**: `CloudWatchAgentServerPolicy` を使う。設定の書き込みが必要なのは初回セットアップ端末のみで、Webサーバー本体には不要。

---

## 4. 構造的な問題（再利用性・保守性）

### 4-1. Outputs に Export が無く、クロススタック参照ができない

連載を通じて、Outputs はあっても `Export` が付いていない。

```yaml
Outputs:
  SecurityGroupIdForEfs:
    Description: The ID of the security group for EFS
    Value: !Ref NaokiSgEfs      # Export が無い
```

`Export` が無ければ `Fn::ImportValue` で参照できない。その結果、後続スタックは**コンソールから値を目視で拾ってパラメータに貼り付ける**運用になっており、実際にRDS記事では `vpc-...` `subnet-...` `sg-...` が直書きされている。

これは IaC の目的である「再現性」を大きく損なう。環境をもう一式作る場合、十数箇所の手作業修正が必要になり、そこで人為ミスが発生する。

さらに、セキュリティグループ記事では5つ作ったSGのうち **EFS と EC2 の2つしか出力されていない**。ALB・RDS・SSM のSG IDは出力すらされていないため、後続スタックからは参照する手段がない。

**対応**: 全てのスタック間受け渡し値に `Export` を付ける。名前の衝突を避けるため `!Sub "${SystemName}-${EnvName}-VpcId"` の形式にする。

---

### 4-2. 名前・CIDR・AZ が全てハードコードされている

VPC記事のテンプレートには `Parameters` セクションが存在せず、`naoki-` という個人名由来の接頭辞、`192.168.1.0/24`、`ap-northeast-2a/2b` が直接書かれている。

同一アカウント内で dev / stg を並行させることも、別リージョンで使うこともできない。

加えて `GroupName` `RoleName` `BackupVaultName` `DBSubnetGroupName` などの物理名がハードコードされているため、**更新時に置換（Replacement）が必要になる変更を加えると「同名リソースが既に存在する」エラーで失敗する**。物理名は原則として CloudFormation に自動生成させるのが安全。

---

### 4-3. リソース間の依存関係が DependsOn で表現されていない

VPC記事で、以下に `DependsOn: NaokiVpcGatewayAttachment` が付いていない。

- `NaokiRoutePublic`（IGW への 0.0.0.0/0 ルート）
- `NaokiNatEip2a` / `NaokiNatEip2b`

CloudFormation は `Ref` / `GetAtt` から依存を自動推論するが、**「IGWがVPCにアタッチされていること」は Ref からは推論できない**。作成順序によっては `Route did not stabilize` や EIP 割り当て失敗が発生する。毎回失敗するわけではなく、タイミング依存で稀に起きるため、原因究明が難しい種類の不具合になる。

---

### 4-4. スタック分割の粒度が記事単位で、依存順序が文書化されていない

テンプレートが「記事1本＝1テンプレート」で分かれており、RDSに至っては1記事の中で3ファイルに分割されている。しかも各記事の冒頭に「先に○○を作っておくこと」という前提が散文で書かれているだけで、機械的に検証できる形になっていない。

著者自身も「作成順序については気をつける必要があると感じました」と書いており、順序依存が運用上の負担になっている。

**対応**: ライフサイクル単位でスタックを分割し、`Export` / `ImportValue` で依存を明示する。ImportValue は参照先が存在しないとエラーになるため、依存関係そのものが順序の検証装置として機能する。

---

## 5. 運用・品質上の指摘

| # | 対象 | 内容 |
|---|---|---|
| 5-1 | VPC | NACL が1つだけで全6サブネットにインバウンド・アウトバウンド全許可。多層防御として機能していない。3層それぞれに適したNACLを分けるべき |
| 5-2 | VPC | `Protocol: '-1'` が文字列型。かつ `-1` 指定時は `PortRange` が無効なのに併記されている |
| 5-3 | VPC | サブネットが `/28`（利用可能11IP）。EFSマウントターゲット・RDS Multi-AZ・将来のAuto Scalingを考えると過小。`/24` 程度が妥当 |
| 5-4 | VPC | 構成図の Protect-2a が `192.168.1.128/28` と記載され Private-2a と重複。コード側は `.160/28` が正しく、図とコードが食い違っている |
| 5-5 | セキュリティグループ | セキュリティグループはステートフルなのに、戻り方向のルール（RDS→EC2:3306、EFS→EC2:2049、SSM→EC2:443）を作成している。全て不要 |
| 5-6 | RDS | `Parameters` の `VPCId` がどのリソースからも参照されていない（2ファイルとも）。cfn-lint W2001 |
| 5-7 | RDS | `DeletionProtection: true` のため `delete-stack` が失敗する。学習環境では削除できず課金が継続する罠 |
| 5-8 | RDS | `MasterUsername` を Secret とは別のパラメータで二重管理しており、不整合の温床 |
| 5-9 | Backup | 対象EC2をインスタンスARNで直接列挙。インスタンス再作成のたびに書き換えが必要。`ListOfTags` によるタグベース選択にすべき |
| 5-10 | Backup | 概要の要件は「EC2とRDSの日次バックアップ」だが、本記事はEC2のみでRDSを除外。AWS Backup で一元管理する意義が薄れている |
| 5-11 | CloudWatch | SNSトピックがプロジェクト全体で3つに分散。メール購読確認が3回必要で、管理点も3箇所 |
| 5-12 | CloudWatch | `AlarmActions` / `OKActions` / `InsufficientDataActions` を全て同一トピックへ。特に `InsufficientDataActions` はEC2停止時に大量通知を生む |
| 5-13 | CloudWatch | アラームが `web01` 単一インスタンス固定。EC2は2台構成なので6アラームを丸ごと複製する必要がある |
| 5-14 | CloudWatch | 要件は「ユーザーデータでエージェント設定」だが、実際は1台目をウィザードで手動設定してから2台目以降のみUserData。**1台目が再現不可能** で IaC の原則から外れている |
| 5-15 | CloudWatch | 検証手順の `epel-release` は Amazon Linux 2023 では利用不可（AL2向け）。指定OSはAL2023なので手順どおりに動かない |
| 5-16 | CloudWatch | エージェント設定の `retention_in_days: -1`（無期限保持）によりログ保管費用が増え続ける |
| 5-17 | Health | SNSターゲットに `SqsParameters: MessageGroupId` を指定。SQS FIFO専用のプロパティでSNSには無意味 |

---

## 6. 採用する設計・しない設計

### 採用するもの

| 項目 | 理由 |
|---|---|
| 3層（Public / Private / Protected）分離 | 業界標準。Web層・アプリ層・DB層の責務分離として妥当 |
| Protect サブネットにデフォルトルートを置かない | 記事の判断は正しい。RDS・EFSはマネージドで外部通信不要 |
| NATゲートウェイをAZごとに配置 | 可用性の観点で正しい。コストとのトレードオフは README に明記する |
| Session Manager + Interface VPCエンドポイント | 踏み台サーバー不要。22番ポートを開けない構成は現代の標準 |
| `eventTypeCategory: issue` によるHealthイベント絞り込み | 通知ノイズを減らす良い工夫 |
| RPO 24時間 / RTO 1日 の要件定義 | バックアップ頻度の根拠として使える。README に記載する |
| CloudWatch Agent 設定を SSM パラメータストアに置く | 複数台展開時に設定を一元化できる。ただし設定投入自体もIaC化する |

### 採用しないもの

| 項目 | 代替 |
|---|---|
| Export 無しの Outputs | 全てのスタック間受け渡しに `Export` を付与 |
| 名前・CIDR・AZ のハードコード | `Parameters` 化。物理名は原則 CloudFormation に自動生成させる |
| 全許可の単一NACL | 3層それぞれに適したNACLを作成 |
| `SecretString` への平文記載 | `ManageMasterUserPassword: true` |
| `CloudWatchAgentAdminPolicy` | `CloudWatchAgentServerPolicy` |
| インスタンスARN直指定のBackup対象 | `ListOfTags` によるタグベース選択 |
| `/28` サブネット | `/24` |
| SNSトピック3分割 | 単一トピックに集約し、TopicPolicy で cloudwatch と events 両方の Principal を許可 |
| 記事単位のスタック分割 | ライフサイクル単位で分割し ImportValue で依存を明示 |

---

## 7. 本プロジェクトでの改善点まとめ（README掲載用）

参考記事に対して、本リポジトリでは以下の改善を行った。

1. **クロススタック参照の全面採用** — 全ての受け渡し値に `Export` を付与し、後続スタックは `Fn::ImportValue` で参照する。参考記事では手動でのリソースID貼り付けが必要だった箇所（VPC ID・サブネットID×2・セキュリティグループID）を全て自動化した。
2. **パラメータ化** — システム名・環境名・リージョン・AZ・全CIDRをパラメータ化し、同一テンプレートで複数環境を構築可能にした。
3. **認証情報の自動生成** — `ManageMasterUserPassword` により、テンプレート・リポジトリ・CloudFormationイベント履歴のいずれにもパスワードが現れない構成とした。
4. **サイレント障害の解消** — AWS Backup の `ScheduleExpression` 欠落と、EventBridge→SNS の `TopicPolicy` 欠落を検出・修正した。いずれもデプロイは成功するが機能しないため、テストなしでは発見できない不具合である。
5. **最小権限の適用** — IAMロールのマネージドポリシーを Admin から Server へ変更した。
6. **多層防御** — 単一の全許可NACLを、Public / Private / Protected の3層それぞれに適したNACLへ分割した。
7. **不要なSGルールの削除** — セキュリティグループのステートフル性を踏まえ、戻り方向のインバウンドルール3件を削除した。
8. **静的解析の導入** — `cfn-lint` を GitHub Actions に組み込み、push のたびに全テンプレートを検証する。全角スペース混入・未使用パラメータ・型不一致は、これで機械的に検出できる。

---

## 8. 次回レビュー対象

以下7記事は未レビュー。特にEC2記事（UserData）とALB記事（HTTPS化・アクセスログ）は本構成の中核であり、S3記事とあわせて重点的に確認する。

- キーペア
- EFS
- SSM
- EC2
- Route53
- ACM
- S3・VPC Flow Logs・ALB access log

---

## 9. EC2記事 — 連載中で最も問題が多い

### 9-1. 【致命】テンプレートに UserData が存在しない

```yaml
      Tags:
        - Key: Name
          Value: naoki-ec2-2a
      UserData:
        #ユーザーデータを記載
```

`UserData:` の値がコメント1行のみ。YAMLとしては null であり、**掲載されているテンプレートには UserData が実質存在しない**。記事の7章に別途スクリプトが載っているが、テンプレートへの埋め込み方は示されていない。

さらに、仮にスクリプトを貼り付けても `Fn::Base64` でラップしないと動作しない。

**正しい書き方**:

```yaml
UserData:
  Fn::Base64: !Sub |
    #!/bin/bash
    set -euxo pipefail
    ...
```

`set -euxo pipefail` を先頭に入れておくと、途中で失敗した際に `/var/log/cloud-init-output.log` で原因を追いやすくなる。

---

### 9-2. 【致命】Parameters の Default が全て空

```yaml
Parameters:
  ImageId:
    Type: String
    Default:            # 値なし
  KeyName:
    Type: AWS::EC2::KeyPair::KeyName
    Default:            # 値なし
  SubnetId:
    Type: AWS::EC2::Subnet::Id
    Default:            # 値なし
```

6個のパラメータ全てで `Default:` が空になっている。YAMLでは null と解釈され、特に `AWS::EC2::KeyPair::KeyName` などの型付きパラメータでは不正な値になる。`cfn-lint` で検出可能。

**対応**: 既定値が無いなら `Default` 行そのものを書かない。書くなら値を入れる。

---

### 9-3. 【重大・セキュリティ】UserData に RDS のパスワードを平文で書いている

```bash
export MYSQL_HOST="RDSのARN"
export MYSQL_USER="ユーザー名"
export MYSQL_PASSWORD="RDSパスワード"
```

UserData はインスタンスメタデータ（IMDS）から取得可能であり、`ec2:DescribeInstanceAttribute` 権限を持つ IAM プリンシパルからも参照できる。**RDS記事でわざわざ Secrets Manager を用意した意味が、ここで完全に消えている。**

しかも同テンプレートには `MetadataOptions` の指定が無く、**IMDSv2 が強制されていない**。IMDSv1 が有効な状態でアプリケーションに SSRF 脆弱性があると、UserData 内の DB パスワードが外部から読み出せる。この2点の組み合わせは実際に事故が起きているパターンで、単独の指摘より深刻度が高い。

**対応**:

```yaml
MetadataOptions:
  HttpTokens: required        # IMDSv2 強制
  HttpPutResponseHopLimit: 1
```

パスワードは UserData に書かず、インスタンス側から IAM ロール経由で Secrets Manager を参照する。

```bash
SECRET=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --query SecretString --output text)
```

なお `MYSQL_HOST` に「RDSのARN」と書かれているのも誤り。MySQL クライアントの接続先は ARN ではなく**エンドポイントアドレス**（`xxx.rds.amazonaws.com`）。

---

### 9-4. 【致命】ヒアドキュメントの向きが逆で、ファイルが1つも作られない

```bash
cat < /etc/httpd/conf.d/php.conf
cat < /mnt/efs/db_config.php
cat < /mnt/efs/index01.php
cat < /mnt/efs/healthcheck.php
```

`cat <` は**入力リダイレクト**であり、ファイルを読み込んで標準出力に出すだけ。ファイルは作成されない。正しくは:

```bash
cat > /mnt/efs/index01.php << 'EOF'
...
EOF
```

4箇所すべてが同じ誤り。ブログのHTMLエスケープで壊れた可能性もあるが、掲載されている状態のままでは Web サーバーは一切構成されない。

なお `<< 'EOF'`（クォート付き）にするか `<< EOF`（クォートなし）にするかで変数展開の有無が変わる。PHPコード内の `$` を展開させたくない場合はクォート付きが必要で、記事では `\$` でエスケープして回避しているが、混乱の元になる。

---

### 9-5. 【誤り】Amazon Linux 2023 に存在しないコマンドを使っている

```bash
if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=http
else
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    service iptables save
fi
```

要件で指定している OS は Amazon Linux 2023 だが、AL2023 には firewalld も iptables-services も標準で入っていない。`service iptables save` は存在しないコマンドで、実行するとエラーになる。

そもそも AWS ではセキュリティグループがインスタンス単位のファイアウォールとして機能するため、**このブロック自体が不要**。OSファイアウォールとSGの二重管理は、障害切り分けを難しくするだけになりやすい。

（CloudWatch記事の `epel-release` も同じく AL2 向けで AL2023 では動かない。連載を通じて AL2 と AL2023 の混同がある。）

---

### 9-6. 【セキュリティ】EFS を転送時暗号化なしでマウントしている

```bash
mount -t nfs4 "${EFS_DNS}:/" /mnt/efs
```

`amazon-efs-utils` を使わず NFSv4 で直接マウントしているため、**EC2–EFS 間の通信が暗号化されていない**。概要記事は「転送時の暗号化の実施」を要件に挙げているが、対象が ALB のHTTPS化のみで EFS が抜けている。

**対応**:

```bash
dnf install -y amazon-efs-utils
mount -t efs -o tls,_netdev fs-xxxxx:/ /mnt/efs
```

fstab にも `nofail` を付ける。付けないと EFS に到達できない状態で再起動した際に、インスタンスが正常に起動しなくなる。

```
fs-xxxxx:/ /mnt/efs efs _netdev,tls,nofail 0 0
```

---

### 9-7. 【バグ】DBの初期データがインスタンス起動のたびに重複する

```sql
CREATE TABLE IF NOT EXISTS employees (...);
INSERT INTO employees (...) VALUES ('Alice', ...), ('Bob', ...);
```

`CREATE TABLE` には `IF NOT EXISTS` があるが、`INSERT` には重複防止が無い。1号機を再作成するたびに従業員データが5件ずつ増え続ける。

そもそもスキーマ投入をWebサーバーのUserDataで行う設計自体が、複数台構成では危険（両インスタンスが同時に実行する可能性がある）。マイグレーションは別プロセスに分離するのが定石。

---

### 9-8. その他

| # | 内容 |
|---|---|
| a | `DisableApiTermination: true` により `delete-stack` が失敗する（RDSの `DeletionProtection` と同じ罠） |
| b | SSM運用なのに `KeyName` を必須にしている。踏み台レス構成ならキーペアは不要で、管理すべき秘密が増えるだけ |
| c | 2台分を別々の手書きテンプレートで作成。UserData の9割が重複コード |
| d | `sed -i 's|||g'` — 空パターンで何もしない（元の `<Directory>` ブロックが欠落した痕跡） |
| e | `Fn::ImportValue` 不使用。サブネット・SG・インスタンスプロファイルを全て手動パラメータで受け渡し |
| f | DocumentRoot を EFS (NFS) に向けている。PHPをNFS越しに実行するのは性能面で不利 |

---

## 10. ALB記事

### 10-1. 【致命】ヘルスチェックパスが誤っており、全ターゲットが Unhealthy になる

```yaml
HealthCheckPath: "/mnt/efs/healthcheck.html"
```

このプロパティには**URLパス**を指定するが、書かれているのは**ファイルシステムパス**。DocumentRoot が `/mnt/efs` なので、この設定では実際に `/mnt/efs/mnt/efs/healthcheck.html` を探しにいき、404 が返る。

さらに拡張子も食い違っている。EC2 の UserData が作成するのは `healthcheck.php` であって `.html` ではない。

そして同じ記事の 6-2 節の解説表には `HealthCheckPath: /healthcheck.php` と書かれており、**コードと表で内容が矛盾している**（表のほうが正しい）。

結果として全ターゲットがヘルスチェックに失敗し、ALB は 503 を返す。**サービス全断**であり、この構成の中で最も影響の大きい不具合。

**対応**: `HealthCheckPath: "/healthcheck.php"`

---

### 10-2. 【セキュリティ】SslPolicy が未指定で TLS 1.0/1.1 が許容される

HTTPSリスナーに `SslPolicy` の指定が無く、既定の `ELBSecurityPolicy-2016-08` が適用される。このポリシーは TLS 1.0 / 1.1 を許容する。

「すべての通信を暗号化します」を掲げる構成としては不十分で、PCI DSS 等のコンプライアンス要件も満たさない。

**対応**:

```yaml
SslPolicy: ELBSecurityPolicy-TLS13-1-2-2021-06
```

---

### 10-3. 【デプロイ順序】アクセスログのS3バケットが先に存在しないと ALB 作成が失敗する

ALB に `access_logs.s3.enabled: true` を設定しているが、保存先バケットとバケットポリシーは次の記事で作成される。ELB のログ配信サービスに `s3:PutObject` を許可するバケットポリシーが無い状態では、**ALB リソースの作成自体が失敗する**。

概要記事の構築手順は「4.ネットワーク構築（ALB）→ 5.ログ収集システム構築（S3）」の順になっており、**手順どおりに進めると必ず詰まる**。S3記事の側では「先にS3を作成しておきましょう」と書かれており、連載内で手順が矛盾している。

---

### 10-4. その他

| # | 内容 |
|---|---|
| a | 6-1節「ALB作成」の解説表が、丸ごと ACM 証明書のプロパティ（DomainName / ValidationMethod / DomainValidationOptions）になっている。ACM記事からのコピペ |
| b | `Targets:` にインスタンスIDを静的登録。Auto Scaling 不可、EC2再作成のたびに手修正が必要 |
| c | `Name: "naoki-alb"` / `"naoki-tg-web"` のハードコードにより、更新時の置換で失敗する |
| d | Route53・ACM・ALB が同一ファイルなのに記事では抜粋掲載のため、そのままコピーできない |

---

## 11. S3・VPC Flow Logs・ALB access log記事

### 11-1. 【致命】バケットポリシーの Principal に「リージョンID」を書いている

```yaml
Principal:
  AWS: "arn:aws:iam::リージョンID:root"
```

IAM ARN の5番目のフィールドは**アカウントID**であり、リージョンIDではない。ARNの構造を取り違えている。

ALB のアクセスログ配信を許可する正しい方法は2つ。

1. **リージョンごとの ELB サービスアカウントIDを指定する**（旧来の方式。東京は `582318560864`）
2. **サービスプリンシパルを使う**（新しいリージョンではこちらが必須）

```yaml
Principal:
  Service: logdelivery.elasticloadbalancing.amazonaws.com
```

いずれにせよ、アカウントIDを書くべき場所である。加えて、`アカウントID` `リージョン` というプレースホルダを手で埋める設計になっているが、CloudFormation には擬似パラメータ `!Ref AWS::AccountId` / `!Ref AWS::Region` があり、これを使えば手修正は不要になる。

---

### 11-2. 【致命】Parameters セクションが無い（3度目）

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description:              # 空

Resources:
  ALBAccessLogsBucket:
    Properties:
      BucketName: !Ref ALBS3BucketName          # 未定義
      ...
              - !Sub "arn:aws:s3:::${ALBS3BucketName}/${ALBS3LogKeyPrefix}*"   # 未定義
```

`ALBS3BucketName` `ALBS3LogKeyPrefix` `VPCS3BucketName` `VPCS3LogKeyPrefix` が全て未定義。VPCフローログ用テンプレートも `S3BucketName` `VPCId` が未定義。`Description:` も空。

CloudWatch・SNS、Health・EventBridge に続き、**3記事目の同じ欠陥**。連載を通じて Parameters を書き忘れる癖がある。

---

### 11-3. 【機能不全】ログ配信先のプレフィックスがポリシーと一致しない

ALB 側は `access_logs.s3.prefix: "alb-logs"` を指定している。一方バケットポリシーの Resource は `${ALBS3BucketName}/${ALBS3LogKeyPrefix}*` で、別の（未定義の）パラメータを参照している。両者が一致しなければ ALB はログを書き込めない。

VPC フローログはさらに明確で、`LogDestination` にプレフィックス指定が無いためバケット直下へ配信しようとするが、ポリシーが許可しているのは `${VPCS3LogKeyPrefix}AWSLogs/アカウントID/*` 配下のみ。**パスが一致しておらず配信が失敗する。**

ログ配信の失敗は例外を投げずに静かに起きるため、S3を覗きに行くまで気づけない。

---

### 11-4. その他

| # | 内容 |
|---|---|
| a | ALB用ポリシーが `s3:GetObject` `s3:ListBucket` まで許可している。ログ配信に必要なのは `s3:PutObject`（＋レガシー用途の `s3:GetBucketAcl`）のみで、過剰権限 |
| b | `AccessControl: Private` を使用。S3のACLは非推奨で、現在は `ObjectOwnership: BucketOwnerEnforced` が既定。`PublicAccessBlockConfiguration` と併用する意味がない |
| c | `BucketEncryption` 未指定 |
| d | ライフサイクルルールが無い。バージョニング有効＋ログ無期限保管で、保管費用が増え続ける。ログバケットにバージョニングを掛ける必要性も薄い |
| e | 6章の解説表が、またしても ACM 証明書のプロパティになっている（ALB記事と同一のコピペ。2度目） |
| f | Outputs に Export が無い（連載共通） |

---

## 12. 追加分を含めた検出件数

| 深刻度 | 初回報告 | 本補遺 | 累計 |
|---|---|---|---|
| 致命（デプロイ不能 / 機能不全） | 9 | 8 | **17** |
| 重大（セキュリティ） | 4 | 4 | **8** |
| 構造的（再利用性） | 5 | 3 | **8** |
| 軽微（品質・運用） | 10+ | 12 | **22+** |

特筆すべき傾向として、**「デプロイは成功するのに機能しない」タイプの不具合が5件**ある。

1. AWS Backup の `ScheduleExpression` 欠落 → バックアップが一度も走らない
2. EventBridge → SNS の `TopicPolicy` 欠落 → 通知が届かない
3. ALB のヘルスチェックパス誤り → 全ターゲット Unhealthy
4. ALB アクセスログのプレフィックス不一致 → ログが保存されない
5. VPC フローログの配信先パス不一致 → ログが保存されない

いずれもコンソール上は正常に見え、CloudFormation もエラーを出さない。**実際に動作テストをしなければ発見できない種類の不具合**であり、この5件を検出できたこと自体が、本プロジェクトでのレビューの成果と言える。

---

## 13. README「参考記事との差分」への追記項目

初回報告の8項目に加えて、以下を追記する。

9. **UserData から認証情報を排除** — 参考記事は RDS のパスワードを UserData に平文で記述していた。本実装ではインスタンスプロファイル経由で Secrets Manager から実行時に取得する方式とし、あわせて IMDSv2 を強制した。
10. **EFS の転送時暗号化** — `amazon-efs-utils` による `mount -t efs -o tls` を採用し、fstab には `nofail` を付与して EFS 到達不可時の起動失敗を回避した。
11. **ヘルスチェック設定の是正** — 参考記事はファイルシステムパスをURLパスとして指定しており、全ターゲットが Unhealthy になる状態だった。
12. **TLSポリシーの明示** — ALB のHTTPSリスナーに `ELBSecurityPolicy-TLS13-1-2-2021-06` を指定し、TLS 1.0/1.1 を無効化した。
13. **ログ配信経路の疎通確認** — バケットポリシーの許可パスと実際の配信先プレフィックスが一致することを、ALB・VPCフローログの双方で確認した。
14. **擬似パラメータの活用** — アカウントID・リージョンを手書きせず `AWS::AccountId` / `AWS::Region` を使用し、環境間の移植性を確保した。
15. **デプロイ順序の是正** — 参考記事の手順ではALBがS3より先に来るためALB作成が失敗する。ログ基盤を先行して構築する順序に変更し、`ImportValue` によって順序依存をコード上で明示した。
