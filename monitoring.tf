locals {
  grafana_allowed_cidr = var.grafana_allowed_cidr != "" ? var.grafana_allowed_cidr : var.dashboard_allowed_cidr
  grafana_secret_name  = var.grafana_secrets_manager_secret_name != "" ? var.grafana_secrets_manager_secret_name : "${var.project_name}/grafana"
  grafana_bootstrap = {
    aws_region                  = var.aws_region
    project_name                = var.project_name
    use_secrets_manager         = var.use_secrets_manager
    secrets_manager_secret_name = var.use_secrets_manager ? local.grafana_secret_name : ""
    grafana_admin_username      = var.grafana_admin_username
    grafana_admin_password      = var.use_secrets_manager ? "USE_SECRETS_MANAGER" : var.grafana_admin_password
    core_asg_name               = aws_autoscaling_group.emqx_core_asg.name
    replicant_asg_name          = aws_autoscaling_group.emqx_replicants_asg.name
    nlb_arn_suffix              = aws_lb.mqtt_nlb.arn_suffix
  }
}

resource "aws_security_group" "grafana_sg" {
  count = var.enable_grafana ? 1 : 0

  name        = "${var.project_name}-grafana-sg"
  description = "Grafana monitoring UI"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Grafana web UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [local.grafana_allowed_cidr]
  }

  ingress {
    description = "SSH troubleshooting"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-grafana-sg"
  })
}

resource "aws_iam_role" "grafana_ec2" {
  count = var.enable_grafana ? 1 : 0

  name               = "${var.project_name}-grafana-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.project_name}-grafana-role"
  })
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch_read" {
  count = var.enable_grafana ? 1 : 0

  role       = aws_iam_role.grafana_ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "grafana_ssm" {
  count = var.enable_grafana ? 1 : 0

  role       = aws_iam_role.grafana_ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "grafana_ec2_extra" {
  count = var.enable_grafana ? 1 : 0

  name = "${var.project_name}-grafana-ec2-extra"
  role = aws_iam_role.grafana_ec2[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "ec2:DescribeInstances",
            "ec2:DescribeTags",
            "autoscaling:DescribeAutoScalingGroups",
            "autoscaling:DescribeAutoScalingInstances",
          ]
          Resource = "*"
        },
      ],
      var.use_secrets_manager ? [
        {
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue",
            "secretsmanager:DescribeSecret",
          ]
          Resource = [aws_secretsmanager_secret.grafana[0].arn]
        },
      ] : []
    )
  })
}

resource "aws_iam_instance_profile" "grafana_ec2" {
  count = var.enable_grafana ? 1 : 0

  name = "${var.project_name}-grafana-profile"
  role = aws_iam_role.grafana_ec2[0].name
}

resource "aws_eip" "grafana_eip" {
  count  = var.enable_grafana ? 1 : 0
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-grafana-eip"
  })
}

resource "aws_instance" "grafana" {
  count = var.enable_grafana ? 1 : 0

  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.grafana_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.grafana_sg[0].id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.grafana_ec2[0].name

  user_data = base64gzip(templatefile("${path.module}/userdata/grafana-bootstrap.sh", merge(local.grafana_bootstrap, {
    dashboard_json = templatefile("${path.module}/userdata/emqx-grafana-dashboard.json.tftpl", {
      region             = var.aws_region
      core_asg_name      = aws_autoscaling_group.emqx_core_asg.name
      replicant_asg_name = aws_autoscaling_group.emqx_replicants_asg.name
      nlb_arn_suffix     = aws_lb.mqtt_nlb.arn_suffix
      project_name       = var.project_name
    })
  })))

  tags = merge(var.tags, {
    Name = "${var.project_name}-grafana"
    Role = "grafana"
  })

  depends_on = [
    aws_autoscaling_group.emqx_core_asg,
    aws_autoscaling_group.emqx_replicants_asg,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eip_association" "grafana" {
  count = var.enable_grafana ? 1 : 0

  instance_id   = aws_instance.grafana[0].id
  allocation_id = aws_eip.grafana_eip[0].id
}
