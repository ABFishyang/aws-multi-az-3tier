# ------------------------------------------------------------------
# 設計方針
# 1. DBのパスワードをUserDataに書かない。インスタンスプロファイル経由で
#    実行時にSecrets Managerから取得する（user_data/web-server.sh.tftpl）。
# 2. MetadataOptionsでIMDSv2を強制する。UserDataはIMDSから読めるため、
#    IMDSv1が有効だとアプリのSSRF脆弱性から認証情報が抜かれる経路になる。
# 3. for_each で2台を1つのリソース定義から生成する。CloudFormation版は
#    素のYAMLで2台分をほぼ手書きコピーする必要があり（Fn::ForEachで
#    後から解消）、Terraformでは最初から for_each で自然に1箇所にできる。
# 4. キーペアは使わない。Session Manager で接続するため不要。
# ------------------------------------------------------------------

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  web_servers = {
    a = { subnet_id = var.private_subnet_ids["a"] }
    b = { subnet_id = var.private_subnet_ids["b"] }
  }
}

resource "aws_instance" "web" {
  for_each = local.web_servers

  ami                     = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type            = var.instance_type
  subnet_id                = each.value.subnet_id
  vpc_security_group_ids    = [var.ec2_security_group_id]
  iam_instance_profile      = var.iam_instance_profile_name
  monitoring                = var.enable_detailed_monitoring
  user_data                 = base64encode(var.user_data)
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                  = "required"
    http_put_response_hop_limit  = 1
  }

  root_block_device {
    volume_type            = "gp3"
    volume_size             = var.root_volume_size
    encrypted                = true
    delete_on_termination    = true
  }

  # AMIの更新だけで既存インスタンスが意図せず再作成されないようにする
  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name   = "${var.project_name}-web-${each.key}"
    Backup = "true"
  }
}
