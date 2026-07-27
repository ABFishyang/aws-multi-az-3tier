# 学習ノート — このプロジェクトで押さえるべきポイント

テンプレートを暗記する必要はありません。**「なぜそう書いたのか」を自分の言葉で説明できる**ことが目標です。
面接では必ず「これはなぜこうしたのですか」と聞かれます。

---

## 目次

1. [CloudFormation の基本構造](#1-cloudformation-の基本構造)
2. [組み込み関数](#2-組み込み関数)
3. [依存関係の扱い](#3-依存関係の扱い)
4. [クロススタック参照](#4-クロススタック参照)
5. [ネットワーク設計](#5-ネットワーク設計)
6. [セキュリティグループと NACL の違い](#6-セキュリティグループと-nacl-の違い)
7. [認証情報の扱い](#7-認証情報の扱い)
8. [よくあるエラーと原因](#8-よくあるエラーと原因)
9. [面接想定問答](#9-面接想定問答)

---

## 1. CloudFormation の基本構造

テンプレートは最大9つのセクションで構成されます。このプロジェクトで使うのは6つです。

| セクション | 必須 | 役割 |
|---|---|---|
| `AWSTemplateFormatVersion` | 任意 | 固定値 `2010-09-09`。バージョンはこれ1つしか存在しない |
| `Description` | 任意 | テンプレートの説明。1024文字まで |
| `Metadata` | 任意 | コンソールでのパラメータ表示順・グループ分け |
| `Parameters` | 任意 | デプロイ時に外部から渡す値 |
| `Conditions` | 任意 | 条件分岐の定義 |
| `Resources` | **必須** | 作成する AWS リソース |
| `Outputs` | 任意 | 他スタックや利用者に渡す値 |

`Resources` だけが必須です。逆に言うと `Resources` が無いテンプレートはエラーになります。

### Parameters の型

```yaml
Parameters:
  ProjectName:
    Type: String              # 汎用の文字列
    Default: myapp
    AllowedPattern: '^[a-z0-9-]+$'   # 正規表現による検証
    ConstraintDescription: 小文字の英数字とハイフンのみ

  AzA:
    Type: AWS::EC2::AvailabilityZone::Name   # AWS 固有の型
    Default: ap-northeast-1a

  MultiAz:
    Type: String
    AllowedValues: ['true', 'false']         # 選択肢を限定
```

**AWS 固有の型を使う利点**: デプロイ前に値の存在チェックが走ります。存在しない AZ 名やサブネット ID を渡した時点でエラーになるため、リソース作成が始まってから失敗するより早く気づけます。

主な AWS 固有型:

| 型 | 用途 |
|---|---|
| `AWS::EC2::AvailabilityZone::Name` | AZ 名 |
| `AWS::EC2::VPC::Id` | VPC ID |
| `AWS::EC2::Subnet::Id` | サブネット ID |
| `AWS::EC2::SecurityGroup::Id` | セキュリティグループ ID |
| `AWS::EC2::KeyPair::KeyName` | キーペア名 |
| `AWS::Route53::HostedZone::Id` | ホストゾーン ID |
| `AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` | SSM パラメータ経由で AMI ID を解決 |

最後の型は 08-compute で使っています。AMI ID をハードコードすると、AMI が更新されるたびに書き換えが必要になりますが、これを使えば常に最新の Amazon Linux 2023 が選ばれます。

```yaml
LatestAmiId:
  Type: AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>
  Default: /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
```

### Conditions

```yaml
Conditions:
  HasCertificate: !Not [!Equals [!Ref CertificateArn, '']]
  NoCertificate: !Equals [!Ref CertificateArn, '']

Resources:
  HttpsListener:
    Type: AWS::ElasticLoadBalancingV2::Listener
    Condition: HasCertificate     # 条件が真のときだけ作成される
```

09-loadbalancer では、これで「証明書があれば HTTPS、無ければ HTTP のみ」を切り替えています。

`Condition:` に書けるのは **`Conditions` セクションで定義した名前** だけです。`!Ref 'AWS::NoValue'` などは書けません（cfn-lint がエラー E3001 で検出します）。

プロパティ単位の分岐には `!If` を使います。

```yaml
MultiAZ: !If [IsMultiAz, true, false]

# 「このプロパティ自体を指定しない」場合は AWS::NoValue
Value: !If
  - UseAccessLogs
  - !ImportValue ...
  - !Ref AWS::NoValue
```

---

## 2. 組み込み関数

### !Ref

対象によって返る値が変わります。**ここが混乱しやすいポイント**です。

| 対象 | 返る値 |
|---|---|
| Parameter | そのパラメータの値 |
| `AWS::EC2::VPC` | VPC ID |
| `AWS::EC2::Subnet` | サブネット ID |
| `AWS::EC2::SecurityGroup` | セキュリティグループ ID |
| `AWS::SNS::Topic` | **トピックの ARN**（ID ではない） |
| `AWS::IAM::Role` | **ロール名**（ARN ではない） |
| `AWS::S3::Bucket` | **バケット名**（ARN ではない） |

IAM ロールと S3 バケットで ARN が欲しいときは `!GetAtt` を使います。

```yaml
!Ref Ec2Role           # → myapp-Ec2Role-XXXXX （ロール名）
!GetAtt Ec2Role.Arn    # → arn:aws:iam::123456789012:role/myapp-Ec2Role-XXXXX
```

### !GetAtt

リソースの属性を取得します。取得できる属性はリソースの種類ごとに決まっています。

```yaml
!GetAtt Vpc.CidrBlock                    # VPC の CIDR
!GetAtt Alb.DNSName                      # ALB の DNS 名
!GetAtt Alb.CanonicalHostedZoneID        # Route53 エイリアス用のゾーン ID
!GetAtt DbInstance.Endpoint.Address      # RDS のエンドポイント（ARN ではない）
!GetAtt DbInstance.MasterUserSecret.SecretArn   # マネージドシークレットの ARN
```

**注意**: MySQL クライアントの接続先は **エンドポイントアドレス** であって ARN ではありません。参考記事はここを取り違えていました。

### !Sub

文字列内に値を埋め込みます。

```yaml
Value: !Sub '${ProjectName}-vpc'
Value: !Sub 'arn:${AWS::Partition}:s3:::${BucketName}/*'
```

**リスト形式**（08-compute の UserData で使用）:

```yaml
UserData:
  Fn::Base64: !Sub
    - |
      #!/bin/bash
      EFS_ID="${EfsId}"
    - EfsId: !ImportValue
        Fn::Sub: '${ProjectName}-EfsFileSystemId'
```

`Fn::Sub` の中には `!ImportValue` を直接書けないため、**第2要素の変数マップで受け渡す**必要があります。

**シェルスクリプトを書くときの落とし穴**: `Fn::Sub` は `${...}` を置換対象とみなします。シェル変数を `${VAR}` と書くと CloudFormation が置換しようとしてエラーになります。

```bash
EFS_ID="${EfsId}"      # ← CloudFormation の置換対象（意図どおり）
echo "$EFS_ID"         # ← 波括弧なし。CloudFormation は無視、シェルが解釈（正しい）
echo "${EFS_ID}"       # ← エラー。CloudFormation が置換しようとする
echo "${!EFS_ID}"      # ← 波括弧が必要な場合の書き方。${EFS_ID} が出力される
```

### 疑似パラメータ

宣言せずに使える組み込み変数です。

| 名前 | 値の例 |
|---|---|
| `AWS::AccountId` | `123456789012` |
| `AWS::Region` | `ap-northeast-1` |
| `AWS::Partition` | `aws`（中国は `aws-cn`、GovCloud は `aws-us-gov`） |
| `AWS::StackName` | スタック名 |
| `AWS::NoValue` | プロパティ自体を削除する |

**ARN を書くときは必ず `AWS::Partition` を使う**のが正しい書き方です。`arn:aws:` と直書きすると中国リージョンや GovCloud で動きません。

---

## 3. 依存関係の扱い

CloudFormation は `!Ref` や `!GetAtt` から依存関係を自動的に推論し、作成順序を決めます。

```yaml
NatGatewayA:
  Properties:
    SubnetId: !Ref PublicSubnetA     # → PublicSubnetA の後に作られる
```

### 自動推論できないケース

**「IGW が VPC にアタッチされていること」は `Ref` からは推論できません。**

```yaml
PublicDefaultRoute:
  Type: AWS::EC2::Route
  DependsOn: IgwAttachment          # ← これが無いと稀に失敗する
  Properties:
    RouteTableId: !Ref PublicRouteTable
    GatewayId: !Ref InternetGateway
```

`!Ref InternetGateway` は「IGW が存在すること」しか保証しません。アタッチ完了は別のリソース（`VPCGatewayAttachment`）の話なので、明示的に `DependsOn` を書く必要があります。

**毎回失敗するわけではなく、タイミング次第で稀に起きる**ため、原因究明が難しい種類の不具合です。参考記事ではこれが抜けていました。

同様に EIP と NAT Gateway にも `DependsOn: IgwAttachment` を付けています。

### 循環参照

ALB のセキュリティグループが EC2 の SG を参照し、EC2 の SG が ALB の SG を参照すると、CloudFormation は「どちらを先に作ればいいか」を決められずエラーになります。

**解決策**: 片方または両方を独立したリソースとして切り出します。

```yaml
# SG 本体は相互参照なしで定義
AlbSg:
  Type: AWS::EC2::SecurityGroup
  Properties:
    SecurityGroupIngress:
      - IpProtocol: tcp
        FromPort: 443
        CidrIp: 0.0.0.0/0      # インターネットからなので循環しない

Ec2Sg:
  Type: AWS::EC2::SecurityGroup
  Properties: {}               # インバウンドは下で別途定義

# 相互参照する部分だけ別リソースにする
AlbToEc2Ingress:
  Type: AWS::EC2::SecurityGroupIngress
  Properties:
    GroupId: !Ref Ec2Sg
    SourceSecurityGroupId: !Ref AlbSg
```

---

## 4. クロススタック参照

### 仕組み

```yaml
# 出力側（01-network）
Outputs:
  VpcId:
    Value: !Ref Vpc
    Export:
      Name: !Sub '${ProjectName}-VpcId'

# 参照側（02-securitygroup）
VpcId: !ImportValue
  Fn::Sub: '${ProjectName}-VpcId'
```

### 3つのルール

1. **Export 名はアカウント・リージョン内で一意**。だから `${ProjectName}` を接頭辞に付けます。付けないと dev と stg を並行できません。
2. **参照されている Export は変更・削除できない**。先に参照側のスタックを消す必要があります。これが削除を逆順で行う理由です。
3. **`Fn::ImportValue` の中で `!ImportValue` と `!Sub` の短縮形は併用できない**。以下のように書きます。

```yaml
# 正しい
VpcId: !ImportValue
  Fn::Sub: '${ProjectName}-VpcId'

# エラーになる
VpcId: !ImportValue !Sub '${ProjectName}-VpcId'
```

### なぜクロススタック参照が重要か

`Export` を付けないと、後続スタックはコンソールから値を目視で拾ってパラメータに貼り付ける運用になります。参考記事では実際に以下のような直書きがありました。

```yaml
VPCId:
  Default: vpc-062d5b30de12cff6a
SubnetIds:
  Default: subnet-06938606508b14fa2,subnet-0ed3deb02f824b0ae
```

環境をもう一式作る場合、十数箇所の手作業修正が必要になり、そこで人為ミスが発生します。IaC の目的である「再現性」が損なわれます。

**副次的な効果**: `ImportValue` は参照先が存在しないとエラーになるため、依存関係そのものがデプロイ順序の検証装置として機能します。順序を間違えると自動的に止まります。

---

## 5. ネットワーク設計

### サブネットの3層構成

| 層 | 配置するもの | インターネットへの経路 |
|---|---|---|
| Public | ALB、NAT Gateway | IGW への直接経路あり |
| Private | EC2 | NAT Gateway 経由（外向きのみ） |
| Protected | RDS、EFS | **なし** |

Protected 層にデフォルトルートを作らない理由: RDS も EFS もマネージドサービスで、OS のアップデートも不要です。NAT への経路は攻撃面を増やすだけになります。VPC 内の通信は自動生成される local ルートで完結します。

### なぜ Private のルートテーブルを AZ ごとに分けるのか

ルートテーブルを1つにまとめると、片方の NAT Gateway にしか経路を向けられません。その AZ が落ちると**もう一方の AZ の EC2 も外部通信できなくなり**、マルチAZ にした意味が消えます。

```
共有した場合:              AZごとに分けた場合:
Private-A ─┐               Private-A ── RT-A ── NAT-A
           ├─ RT ── NAT-A  Private-B ── RT-B ── NAT-B
Private-B ─┘
           ↑ NAT-A が落ちると両方死ぬ
```

### サブネットの CIDR とホスト数

AWS は各サブネットで **5つの IP を予約** します（ネットワークアドレス、VPC ルーター、DNS、将来用、ブロードキャスト）。

| CIDR | 全 IP | 利用可能 |
|---|---|---|
| /28 | 16 | 11 |
| /26 | 64 | 59 |
| /24 | 256 | 251 |

参考記事は /28 でしたが、EFS マウントターゲット・RDS Multi-AZ・将来の Auto Scaling を考えると 11個は足りません。本プロジェクトでは /24 を使っています。

---

## 6. セキュリティグループと NACL の違い

| | セキュリティグループ | ネットワーク ACL |
|---|---|---|
| 適用対象 | ENI（インスタンス単位） | サブネット単位 |
| ステート | **ステートフル** | **ステートレス** |
| ルール | 許可のみ | 許可と拒否 |
| 評価 | 全ルールを評価 | 番号順に評価、最初に一致したもので確定 |
| ソース指定 | CIDR と**セキュリティグループ ID** | CIDR のみ |

### ステートフルの意味 — ここが最重要

セキュリティグループは**戻りの通信を自動的に許可**します。

```
EC2 → RDS:3306 を許可した場合

  EC2 (ephemeral:52341) ──→ RDS (3306)      ← インバウンドルールで許可
  EC2 (ephemeral:52341) ←── RDS (3306)      ← 自動的に許可される
```

したがって **RDS の SG に「EC2 → 3306」を書けば十分**で、EC2 の SG に「RDS → 3306」を書く必要はありません。

参考記事は以下の3つの不要なルールを作っていました。

- `NaokiEc2IngressDb` (RDS → EC2 : 3306)
- `NaokiEc2IngressEfs` (EFS → EC2 : 2049)
- `NaokiEc2IngressSsm` (SSM → EC2 : 443)

いずれも EC2 が発信側なので、応答は自動的に通ります。

### ステートレスの意味

NACL は戻りの通信も明示的に許可する必要があります。だから **エフェメラルポート（1024-65535）の許可が必須** になります。

```yaml
# Private サブネットが NAT 経由で外部と通信した戻りを受けるため
PrivateNaclInEphemeral:
  Properties:
    RuleNumber: 110
    Protocol: 6
    Egress: false
    CidrBlock: 0.0.0.0/0        # ← 送信元はインターネット側のまま
    PortRange:
      From: 1024
      To: 65535
```

「NAT を通ったのに送信元が 0.0.0.0/0 なのはなぜか」— NAT が変換するのは**内側の**アドレスであり、応答パケットの送信元はインターネット上のサーバーのままだからです。

### SG をソースに指定する利点

```yaml
SecurityGroupIngress:
  - IpProtocol: tcp
    FromPort: 3306
    SourceSecurityGroupId: !Ref Ec2Sg    # IP ではなく SG を指定
```

EC2 の IP アドレスが変わっても、インスタンスが増えても、設定を変更する必要がありません。**SG チェーン** と呼ばれる基本パターンです。

```
Internet → AlbSg → Ec2Sg → RdsSg / EfsSg / VpceSg
```

---

## 7. 認証情報の扱い

### やってはいけないこと

```yaml
# 参考記事の書き方 — テンプレートに平文でパスワード
SecretString: '{"username": "admin", "password": "P@ssw0rd"}'
```

```bash
# 参考記事の UserData — さらに危険
export MYSQL_PASSWORD="RDSパスワード"
```

UserData は **インスタンスメタデータ（IMDS）から読み取れます**。また `ec2:DescribeInstanceAttribute` 権限を持つ IAM プリンシパルからも参照できます。

### 正しいやり方

**1. RDS にパスワードを生成・管理させる**

```yaml
ManageMasterUserPassword: true
```

これだけで RDS が Secrets Manager にシークレットを自動生成し、ローテーションまで管理します。テンプレート・Git・CloudFormation のイベント履歴のいずれにもパスワードが現れません。

**2. EC2 は実行時に取得する**

```bash
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" --query SecretString --output text)
DB_PASS=$(echo "$SECRET_JSON" | jq -r .password)
```

IAM ロールは特定のシークレットにのみ許可します。

```yaml
- Effect: Allow
  Action: secretsmanager:GetSecretValue
  Resource:
    - !Sub 'arn:${AWS::Partition}:secretsmanager:${AWS::Region}:${AWS::AccountId}:secret:rds!db-*'
```

**3. IMDSv2 を強制する**

```yaml
MetadataOptions:
  HttpTokens: required
  HttpPutResponseHopLimit: 1
```

IMDSv1 はただの HTTP GET でメタデータを返すため、アプリケーションに SSRF 脆弱性があると外部から読まれます。IMDSv2 は PUT でセッショントークンを取得する必要があるため、単純な SSRF では到達できません。

`HttpPutResponseHopLimit: 1` は、コンテナなど別ネットワーク名前空間からの取得を防ぎます。

**この2つは組み合わせて初めて防御として完成します。** 認証情報を置かないこと（1・2）と、置いてしまった場合の被害を抑えること（3）は別の話です。

---

## 8. よくあるエラーと原因

| エラーメッセージ | 原因 | 対処 |
|---|---|---|
| `Unresolved resource dependencies [X]` | `!Ref X` の X が Parameters にも Resources にも無い | 定義を追加する |
| `No export named X found` | 依存スタックが未デプロイ、または Export 名の綴り違い | デプロイ順序を確認 |
| `Export X cannot be deleted as it is in use` | 参照しているスタックが残っている | 参照側を先に削除 |
| `Circular dependency between resources` | リソースが相互参照している | 片方を独立リソースに切り出す |
| `Route did not stabilize` | IGW アタッチ前にルートを作成した | `DependsOn: IgwAttachment` |
| `InvalidPermission.Duplicate` | 同じ SG ルールを二重に定義した | インラインか別リソースか一方に統一 |
| `Template format error: YAML not well-formed` | 全角スペース混入、インデント誤り、タブ使用 | 後述 |
| `Value of property X must be of type Y` | 型不一致（`'300'` と `300` など） | 引用符を外す／付ける |
| `DeleteStack failed: ... has deletion protection` | `DeletionProtection` / `DisableApiTermination` が true | 先に false へ更新してから削除 |

### 全角スペース（U+3000）

日本語入力のまま空白を打つと混入します。**エディタ上では半角スペースと見分けがつきません。**

```yaml
DBSubnetGroupName: !Ref DBSubnetGroupName　# グループ名
                                          ↑ ここが全角スペース
```

YAML では全角スペースは空白文字として扱われないため、`#` 以降がコメントとして認識されず値の一部になります。

**対策**:

- VS Code は全角スペースを枠付きで表示します（設定 `editor.unicodeHighlight.ambiguousCharacters`）
- 本リポジトリの GitHub Actions で `grep -P '\x{3000}'` により自動検出しています

### YAML の基本ルール

- インデントは**半角スペースのみ**。タブは使用不可
- コロンの後には**必ず半角スペース**（`Type: String` であって `Type:String` ではない）
- `Default:` と書いて値を書かないと **null** になる。値が無いなら行ごと削除する

---

## 9. 面接想定問答

### Q1. このプロジェクトで一番工夫した点は何ですか

参考にした技術ブログのコードをレビューし、「デプロイは成功するのに機能しない」タイプの不具合を5件検出したことです。

たとえば AWS Backup のバックアッププランに `ScheduleExpression` が抜けており、プランもルールも正常に作成されるのに、日次バックアップが一度も実行されない状態になっていました。CloudFormation はエラーを出さず、マネジメントコンソール上も正常に見えるため、実際にバックアップの実行履歴を確認するまで気づけません。

こうした不具合は、必要になった瞬間まで発覚しないため、実務では最も損害が大きい部類だと考えています。

### Q2. なぜ踏み台サーバーを置かなかったのですか

Session Manager を使うことで、22番ポートを一切開放せずに EC2 へ接続できるためです。鍵の配布と失効管理、OS のパッチ適用、踏み台自体の稼働コストがすべて不要になり、操作ログも CloudTrail に自動記録されます。

そのために ssm / ssmmessages / ec2messages の3つの Interface VPC エンドポイントが必要で、1つでも欠けるとセッションが確立できません。

**トレードオフ**としては、Interface エンドポイントは1つあたり月額約7ドルかかるため、小規模構成ではコスト面で不利になります。

### Q3. NAT ゲートウェイを2台にしたのはなぜですか

AZ 障害時にもう一方の AZ が巻き込まれないようにするためです。

Private サブネットのルートテーブルを1つにまとめると、片方の NAT にしか経路を向けられません。その AZ が落ちると、もう一方の AZ の EC2 も外部通信できなくなり、マルチAZ 構成にした意味が失われます。

**トレードオフ**は費用で、NAT ゲートウェイは1台あたり月額約35ドル、2台で約70ドルとこの構成で最も高額な部分になります。要件次第では1台に減らす判断もあり得ますが、その場合は可用性が下がることを明示すべきだと考えています。

### Q4. Protected サブネットにデフォルトルートを置かなかった理由は

RDS と EFS はマネージドサービスで、OS のアップデートも外部 API 呼び出しも不要だからです。NAT への経路を持たせても使い道がなく、攻撃面を増やすだけになります。VPC 内の通信は自動生成される local ルートで完結します。

### Q5. セキュリティグループで気をつけた点は

2点あります。

1つ目は、ソースに CIDR ではなくセキュリティグループ ID を指定したことです。IP が変わってもインスタンスが増えても設定を追従させる必要がなくなります。

2つ目は、**戻り方向のルールを作らなかった**ことです。セキュリティグループはステートフルなので、EC2 → RDS:3306 を許可すれば応答は自動的に通ります。参考記事では RDS → EC2、EFS → EC2、SSM → EC2 の3つの不要なルールが作られていました。

### Q6. ネットワーク ACL とセキュリティグループはどう使い分けましたか

セキュリティグループをインスタンス単位の主要な制御に、ネットワーク ACL をサブネット単位の補助的な防御層として使いました。

ネットワーク ACL はステートレスなので、戻り通信のためにエフェメラルポート（1024-65535）の許可が必要になります。Private 層では、NAT 経由の外向き通信の応答を受けるため、送信元 0.0.0.0/0 からのエフェメラルポートを許可しています。NAT が変換するのは内側のアドレスなので、応答パケットの送信元はインターネット上のサーバーのままだからです。

参考記事は全サブネット共通の1つの NACL で全許可にしており、多層防御になっていませんでした。

### Q7. データベースのパスワードはどう管理していますか

`ManageMasterUserPassword: true` を指定し、RDS 自身に Secrets Manager でのパスワード生成・保管・ローテーションを任せています。テンプレート、Git リポジトリ、CloudFormation のイベント履歴のいずれにもパスワードが現れません。

EC2 側はインスタンスプロファイル経由で、起動時に Secrets Manager から取得します。IAM ポリシーは対象のシークレットにのみ限定しています。

あわせて IMDSv2 を強制しました。認証情報を UserData に置かないことと、置いてしまった場合の被害を抑えることは別の話なので、両方必要だと考えています。

### Q8. 一番苦労した点は何ですか

（※実際に構築して詰まった箇所を、以下の形式で自分の言葉に置き換えてください）

- **事象**: 何が起きたか
- **切り分け**: どう調べたか（CloudFormation のイベントタブ、`/var/log/cloud-init-output.log`、ターゲットグループのヘルス状態 など）
- **原因**: 何が原因だったか
- **対応**: どう直したか
- **学び**: 次から何に気をつけるか

素材になりやすい箇所:

- クロススタック参照の削除順序（`Export cannot be deleted as it is in use`）
- ALB のターゲットが Unhealthy のまま（ヘルスチェックパス、SG、Apache の起動）
- EFS がマウントできない（NACL の 2049、amazon-efs-utils の有無）
- RDS の作成に失敗（エンジンバージョンのサポート終了）
- UserData が動かない（Base64、`/var/log/cloud-init-output.log` の確認方法）

### Q9. 改善したい点はありますか

3点あります。

1つ目は Auto Scaling Group の導入です。現在は EC2 を静的に2台配置していますが、負荷に応じた増減ができず、インスタンス障害時の自動復旧もありません。

2つ目は CI/CD パイプラインです。現在は cfn-lint による静的解析までを GitHub Actions で自動化していますが、デプロイは手動です。

3つ目は Terraform での再実装です。ツールによる設計思想の違いを比較したいと考えています。

### Q10. コストはどれくらいかかりますか

月額で約160ドル程度です。内訳は NAT ゲートウェイ2台で約70ドル、VPC エンドポイント3つで約21ドル、RDS の Multi-AZ で約30ドル、EC2 2台で約17ドル、ALB で約18ドルです。

学習目的では、動作確認後に逆順で全スタックを削除する運用にしています。費用を抑える場合は NAT を1台に減らす、RDS を Single-AZ にするといった選択肢がありますが、いずれも可用性とのトレードオフになります。

---

## 復習の進め方

1. **まず 01-network を通して読む** — コメントを含めて、なぜその設定なのかを追う
2. **各テンプレート冒頭の「設計方針・参考記事からの修正点」を読む** — ここが面接の答えの原型
3. **実際にデプロイする** — 読むだけでは詰まる場所が分からない
4. **わざと壊してみる** — ヘルスチェックパスを間違えるとどうなるか、NACL の 2049 を消すとどうなるか。**エラーの見え方を知っていることが実務で一番効く**
5. **Q8 の「苦労した点」を自分の経験で埋める** — これが埋まって初めて、この作品集は「作った」と言える状態になる
