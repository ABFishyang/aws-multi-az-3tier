.PHONY: init fmt validate lint lint-init docs plan apply destroy clean

init:
	terraform init

fmt:
	terraform fmt -recursive

validate: init
	terraform validate

# tflint --init は初回のみ必要（.tflint.hcl のプラグインをダウンロードする）
lint-init:
	tflint --init

lint:
	tflint --recursive --format compact

# terraform-docs でモジュール／ルートの README.md を再生成する
docs:
	terraform-docs -c .terraform-docs.yml modules/network
	terraform-docs -c .terraform-docs.yml modules/security
	terraform-docs -c .terraform-docs.yml modules/iam
	terraform-docs -c .terraform-docs.yml modules/endpoints
	terraform-docs -c .terraform-docs.yml modules/logging
	terraform-docs -c .terraform-docs.yml modules/storage
	terraform-docs -c .terraform-docs.yml modules/database
	terraform-docs -c .terraform-docs.yml modules/compute
	terraform-docs -c .terraform-docs.yml modules/loadbalancer
	terraform-docs -c .terraform-docs.yml modules/dns
	terraform-docs -c .terraform-docs.yml modules/monitoring
	terraform-docs -c .terraform-docs.yml modules/backup
	terraform-docs -c .terraform-docs-root.yml .

plan: validate
	terraform plan -out=tfplan

apply:
	terraform apply tfplan

destroy:
	terraform plan -destroy -out=destroy.tfplan
	terraform apply destroy.tfplan

clean:
	rm -f tfplan destroy.tfplan
	rm -rf .terraform
