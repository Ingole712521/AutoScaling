resource "aws_security_group" "nlb_sg" {
  name        = "${var.project_name}-nlb-sg"
  description = "Allow MQTT traffic into NLB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MQTT from internet"
    from_port   = 1883
    to_port     = 1883
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-nlb-sg"
  })
}

resource "aws_security_group" "emqx_nodes_sg" {
  name        = "${var.project_name}-emqx-cluster-sg"
  description = "Production security framework for core and auto-scaled replicant instances"
  vpc_id      = aws_vpc.main.id

  # Edge Client Traffic
  ingress {
    description = "Allow inbound MQTT data lane traffic from edge load balancer"
    from_port   = 1883
    to_port     = 1883
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow inbound EMQX dashboard access"
    from_port   = 18083
    to_port     = 18083
    protocol    = "tcp"
    cidr_blocks = [var.dashboard_allowed_cidr]
  }

  ingress {
    description = "Allow SSH troubleshooting access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # Internal cluster communication between nodes sharing this security group
  ingress {
    description = "Allow inter-node cluster communication within this security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow full egress traffic to secure external dependencies"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-emqx-cluster-sg"
  })
}
