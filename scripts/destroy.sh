#!/usr/bin/env bash
#
# 全スタックを逆順で削除する
#
#   使い方:
#     ./scripts/destroy.sh
#
#   注意:
#     ログ用 S3 バケットと Backup ボールトは DeletionPolicy: Retain のため
#     スタック削除後も残ります。不要であれば手動で削除してください。
#
set -euo pipefail

PROJECT="${PROJECT:-myapp}"
REGION="${REGION:-ap-northeast-1}"

# デプロイ順の逆
STACKS=(
  "12-backup"
  "11-monitoring"
  "10-dns"
  "09-loadbalancer"
  "08-compute"
  "07-database"
  "06-storage"
  "05-logging"
  "04-endpoint"
  "03-iam"
  "02-securitygroup"
  "01-network"
)

echo "以下のスタックを削除します（プロジェクト: $PROJECT / リージョン: $REGION）"
printf '  %s\n' "${STACKS[@]}"
read -r -p "続行しますか? [y/N] " ans
[[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "中止しました"; exit 0; }

for s in "${STACKS[@]}"; do
  stack="${PROJECT}-${s}"
  if ! aws cloudformation describe-stacks --region "$REGION" --stack-name "$stack" >/dev/null 2>&1; then
    echo "スキップ: $stack (存在しません)"
    continue
  fi
  echo "削除中: $stack"
  aws cloudformation delete-stack --region "$REGION" --stack-name "$stack"
  aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$stack"
  echo "完了:   $stack"
done

echo ""
echo "全スタックの削除が完了しました。"
echo "残存リソースの確認:"
echo "  aws s3 ls | grep ${PROJECT}"
echo "  aws backup list-backup-vaults --region $REGION"
