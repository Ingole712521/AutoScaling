data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "core" {
  for_each = var.nodes

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[each.value.subnet_index]
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = var.instance_profile_name

  user_data = templatefile(var.core_userdata_template_path, {
    node_name          = "emqx@${each.value.dns}.${var.zone_name}"
    node_cookie        = var.node_cookie
    dashboard_username = var.dashboard_username
    dashboard_password = var.dashboard_password
    seed_nodes         = jsonencode(var.core_seed_hosts)
  })

  tags = merge(var.tags, {
    Name = each.value.name
    Role = "emqx-core"
  })
}
