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
  name        = "${var.project_name}-emqx-nodes-sg"
  description = "Internal EMQX core/replicant node communication and MQTT"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MQTT from NLB SG"
    from_port       = 1883
    to_port         = 1883
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb_sg.id]
  }

  ingress {
    description = "EMQX dashboard management"
    from_port   = 18083
    to_port     = 18083
    protocol    = "tcp"
    cidr_blocks = [var.dashboard_allowed_cidr]
  }

  ingress {
    description = "Erlang distribution"
    from_port   = 4370
    to_port     = 4370
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "EMQX cluster communication"
    from_port   = 5370
    to_port     = 5370
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-emqx-nodes-sg"
  })
}
