resource "aws_security_group" "nlb" {
  name        = "${var.project_name}-nlb-sg"
  description = "NLB ingress for MQTT traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "MQTT TCP"
    from_port   = 1883
    to_port     = 1883
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MQTT TLS TCP"
    from_port   = 8883
    to_port     = 8883
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-nlb-sg" })
}

resource "aws_security_group" "core" {
  name        = "${var.project_name}-core-sg"
  description = "Core node security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "Dashboard access"
    from_port   = 18083
    to_port     = 18083
    protocol    = "tcp"
    cidr_blocks = [var.dashboard_allowed_cidr]
  }

  ingress {
    description = "EMQX internal cluster traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-core-sg" })
}

resource "aws_security_group" "replicant" {
  name        = "${var.project_name}-replicant-sg"
  description = "Replicant node security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MQTT from NLB"
    from_port       = 1883
    to_port         = 1883
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  ingress {
    description     = "MQTT TLS from NLB"
    from_port       = 8883
    to_port         = 8883
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "Dashboard access"
    from_port   = 18083
    to_port     = 18083
    protocol    = "tcp"
    cidr_blocks = [var.dashboard_allowed_cidr]
  }

  ingress {
    description = "EMQX internal cluster traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-replicant-sg" })
}

# Separate rules avoid core <-> replicant security group cycle.
resource "aws_security_group_rule" "core_from_replicant" {
  type                     = "ingress"
  security_group_id        = aws_security_group.core.id
  source_security_group_id = aws_security_group.replicant.id
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  description              = "Cluster traffic from replicants"
}

resource "aws_security_group_rule" "replicant_from_core" {
  type                     = "ingress"
  security_group_id        = aws_security_group.replicant.id
  source_security_group_id = aws_security_group.core.id
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  description              = "Cluster traffic from core nodes"
}
