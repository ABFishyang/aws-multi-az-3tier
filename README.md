# AWS Multi-AZ 3-Tier Architecture

このリポジトリでは、AWS 上にマルチ AZ の 3 層 Web アーキテクチャを構築する 2 つの Infrastructure as Code 実装を公開しています。

## 実装を選択

| バージョン | ブランチ | 概要 |
| --- | --- | --- |
| Terraform | [`terraform`](https://github.com/ABFishyang/aws-multi-az-3tier/tree/terraform) | Terraform モジュール、変数、検証ワークフローを含む実装 |
| CloudFormation | [`cloudformation`](https://github.com/ABFishyang/aws-multi-az-3tier/tree/cloudformation) | ネストされた CloudFormation スタック、パラメータ、デプロイスクリプトを含む実装 |

各ブランチは独立した実装です。利用したいバージョンのブランチを選択し、そのブランチの README に従ってデプロイしてください。

## ライセンス

MIT License. See [LICENSE](LICENSE).
