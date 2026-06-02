data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "emqx_core" {
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = var.core_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.emqx_nodes_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl gnupg apt-transport-https ca-certificates lsb-release

    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

    curl -fsSL https://assets.emqx.com/scripts/install-emqx-deb.sh | bash
    apt-get update -y
    apt-get install -y emqx

    cat > /etc/emqx/emqx.conf <<EOF
node {
  name = "emqx@$${PRIVATE_IP}"
  cookie = "${var.emqx_node_cookie}"
  role = core
}

cluster {
  discovery_strategy = static
  static {
    seeds = ["emqx@$${PRIVATE_IP}"]
  }
}

dashboard {
  default_username = "${var.emqx_dashboard_username}"
  default_password = "${var.emqx_dashboard_password}"
}
EOF

    systemctl enable emqx
    systemctl restart emqx
  EOT

  tags = merge(var.tags, {
    Name = "${var.project_name}-core-1"
    Role = "emqx-core"
  })
}

resource "aws_eip" "core_eip" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-core-eip"
  })
}

resource "aws_eip_association" "core_eip_assoc" {
  instance_id   = aws_instance.emqx_core.id
  allocation_id = aws_eip.core_eip.id
}
