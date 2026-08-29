#!/usr/bin/env bash
#
# 全スタックを依存順にデプロイする
#
#   使い方:
#     bash cloudformation/scripts/deploy.sh        # 01 から 12 まで順にデプロイ
#     bash cloudformation/scripts/deploy.sh 05     # 05 だけデプロイ
#     bash cloudformation/scripts/deploy.sh 05 09  # 05 から 09 までデプロイ
#
#   環境変数:
#     PROJECT   プロジェクト名 (既定: myapp)
#     REGION    リージョン     (既定: ap-northeast-1)
#     EMAIL     通知先メール   (11-monitoring で必須)
#     CERT_ARN       既存の ACM 証明書 ARN（任意）
#     DOMAIN_NAME    新しく証明書と Route 53 レコードを作成するドメイン（任意）
#     HOSTED_ZONE_ID DOMAIN_NAME のパブリックホストゾーン ID（任意）
#
set -euo pipefail

PROJECT="${PROJECT:-myapp}"
REGION="${REGION:-ap-northeast-1}"
EMAIL="${EMAIL:-}"
CERT_ARN="${CERT_ARN:-}"
DOMAIN_NAME="${DOMAIN_NAME:-}"
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-}"

if [[ -n "$DOMAIN_NAME" && -z "$HOSTED_ZONE_ID" ]]; then
  echo "ERROR: DOMAIN_NAME を指定する場合は HOSTED_ZONE_ID も必要です" >&2
  exit 1
fi

if [[ -z "$DOMAIN_NAME" && -n "$HOSTED_ZONE_ID" ]]; then
  echo "ERROR: HOSTED_ZONE_ID を指定する場合は DOMAIN_NAME も必要です" >&2
  exit 1
fi

if [[ -n "$CERT_ARN" && -n "$DOMAIN_NAME" ]]; then
  echo "ERROR: CERT_ARN と DOMAIN_NAME/HOSTED_ZONE_ID は同時に指定できません" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

STACKS=(
  "01-network"
  "02-securitygroup"
  "03-iam"
  "04-endpoint"
  "05-logging"
  "06-storage"
  "07-database"
  "08-compute"
  "09-loadbalancer"
  "11-monitoring"
  "12-backup"
)
# 10-dns は独自ドメインが必要なため既定の一覧から外している

FROM="${1:-01}"
TO="${2:-99}"

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: AWS CLI v2 が必要です" >&2
  exit 1
fi

# 11-monitoring を対象に含む場合は、課金リソースを作り始める前に必須値を確認する。
if [[ "$FROM" < "12" && "$TO" > "10" && -z "$EMAIL" ]]; then
  echo "ERROR: 11-monitoring を含む実行には EMAIL 環境変数が必要です" >&2
  exit 1
fi

deploy_one() {
  local name="$1"
  local num="${name%%-*}"
  local params=("ProjectName=$PROJECT")
  local caps=()

  case "$name" in
    03-iam)         caps=(--capabilities CAPABILITY_IAM) ;;
    09-loadbalancer)
      if [[ -n "$CERT_ARN" ]]; then
        params+=("CertificateArn=$CERT_ARN")
      fi
      ;;
    11-monitoring)
      if [[ -z "$EMAIL" ]]; then
        echo "ERROR: 11-monitoring には EMAIL 環境変数が必要です" >&2
        exit 1
      fi
      params+=("NotificationEmail=$EMAIL")
      ;;
  esac

  echo ""
  echo "=============================================="
  echo " Deploying ${PROJECT}-${name}"
  echo "=============================================="

  aws cloudformation deploy \
    --region "$REGION" \
    --template-file "templates/${name}.yaml" \
    --stack-name "${PROJECT}-${name}" \
    --parameter-overrides "${params[@]}" \
    --no-fail-on-empty-changeset \
    "${caps[@]+"${caps[@]}"}"
}

deploy_dns_and_enable_https() {
  echo ""
  echo "=============================================="
  echo " Deploying ${PROJECT}-10-dns"
  echo "=============================================="

  aws cloudformation deploy \
    --region "$REGION" \
    --template-file "templates/10-dns.yaml" \
    --stack-name "${PROJECT}-10-dns" \
    --parameter-overrides \
      "ProjectName=$PROJECT" \
      "DomainName=$DOMAIN_NAME" \
      "HostedZoneId=$HOSTED_ZONE_ID" \
    --no-fail-on-empty-changeset

  local certificate_arn
  certificate_arn=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "${PROJECT}-10-dns" \
    --query "Stacks[0].Outputs[?OutputKey=='CertificateArn'].OutputValue" \
    --output text)

  if [[ -z "$certificate_arn" || "$certificate_arn" == "None" ]]; then
    echo "ERROR: ${PROJECT}-10-dns から CertificateArn を取得できません" >&2
    exit 1
  fi

  echo "Updating ${PROJECT}-09-loadbalancer to HTTPS"
  CERT_ARN="$certificate_arn" deploy_one "09-loadbalancer"
}

for s in "${STACKS[@]}"; do
  num="${s%%-*}"
  if [[ "$num" < "$FROM" ]] || [[ "$num" > "$TO" ]]; then
    continue
  fi
  deploy_one "$s"

  # 10-dns は 09-loadbalancer のエクスポートを参照するため、まずHTTPの
  # ALBを作成する。その後に証明書とAliasを作り、09を証明書ARN付きで更新する。
  if [[ "$s" == "09-loadbalancer" && -n "$DOMAIN_NAME" ]]; then
    deploy_dns_and_enable_https
  fi
done

echo ""
echo "=============================================="
echo " 完了"
echo "=============================================="
ALB_DNS=$(aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "${PROJECT}-09-loadbalancer" \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" \
  --output text 2>/dev/null || echo "")
if [[ -n "$ALB_DNS" ]]; then
  if [[ -n "$DOMAIN_NAME" ]]; then
    echo " Site URL: https://${DOMAIN_NAME}/"
  elif [[ -n "$CERT_ARN" ]]; then
    echo " HTTPS: enabled（証明書の対象ドメインからアクセスしてください）"
    echo " ALB DNS: ${ALB_DNS}"
  else
    echo " ALB URL: http://${ALB_DNS}/"
  fi
fi
echo " 11-monitoring をデプロイした場合、SNS の購読確認メールを承認してください。"
