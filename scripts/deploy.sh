#!/usr/bin/env bash
#
# 全スタックを依存順にデプロイする
#
#   使い方:
#     ./scripts/deploy.sh                    # 01 から 12 まで順にデプロイ
#     ./scripts/deploy.sh 05                 # 05 だけデプロイ
#     ./scripts/deploy.sh 05 09              # 05 から 09 までデプロイ
#
#   環境変数:
#     PROJECT   プロジェクト名 (既定: myapp)
#     REGION    リージョン     (既定: ap-northeast-1)
#     EMAIL     通知先メール   (11-monitoring で必須)
#     CERT_ARN  ACM 証明書 ARN (省略時は ALB を HTTP のみで構築)
#
set -euo pipefail

PROJECT="${PROJECT:-myapp}"
REGION="${REGION:-ap-northeast-1}"
EMAIL="${EMAIL:-}"
CERT_ARN="${CERT_ARN:-}"

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

for s in "${STACKS[@]}"; do
  num="${s%%-*}"
  if [[ "$num" < "$FROM" ]] || [[ "$num" > "$TO" ]]; then
    continue
  fi
  deploy_one "$s"
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
  echo " ALB URL: http://${ALB_DNS}/"
fi
echo " 11-monitoring をデプロイした場合、SNS の購読確認メールを承認してください。"
