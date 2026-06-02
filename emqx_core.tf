resource "aws_instance" "emqx_core" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.core_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.emqx_nodes_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    yum update -y
    amazon-linux-extras install docker -y
    systemctl enable docker
    systemctl start docker

    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

    docker pull emqx/emqx:latest
    docker rm -f emqx || true
    docker run -d --name emqx --restart always \
      -p 1883:1883 \
      -p 18083:18083 \
      -p 4370:4370 \
      -p 5370:5370 \
      -e EMQX_NODE__ROLE=core \
      -e EMQX_NODE__NAME=emqx@$${PRIVATE_IP} \
      -e EMQX_CLUSTER__DISCOVERY_STRATEGY=static \
      -e EMQX_CLUSTER__STATIC__SEEDS="[emqx@$${PRIVATE_IP}]" \
      -e EMQX_NODE__COOKIE=${var.emqx_node_cookie} \
      -e EMQX_DASHBOARD__DEFAULT_USERNAME=${var.emqx_dashboard_username} \
      -e EMQX_DASHBOARD__DEFAULT_PASSWORD=${var.emqx_dashboard_password} \
      emqx/emqx:latest
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
