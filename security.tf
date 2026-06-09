resource "aws_security_group" "nlb_sg" {
  name        = "${var.project_name}-nlb-sg"
  description = "Allow MQTT traffic into NLB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MQTT plaintext from internet"
    from_port   = 1883
    to_port     = 1883
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.enable_mqtt_tls ? [1] : []
    content {
      description = "MQTT over TLS from internet (ACM termination at NLB)"
      from_port   = 8883
      to_port     = 8883
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
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
  description = "EMQX core and replicant nodes; MQTT only from NLB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MQTT from Network Load Balancer only"
    from_port       = 1883
    to_port         = 1883
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb_sg.id]
  }

  ingress {
    description = "EMQX dashboard (core management)"
    from_port   = 18083
    to_port     = 18083
    protocol    = "tcp"
    cidr_blocks = [var.dashboard_allowed_cidr]
  }

  ingress {
    description = "SSH troubleshooting"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "Inter-node cluster traffic (Erlang distribution, RPC)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Egress for packages, SSM, and cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-emqx-cluster-sg"
  })
}
