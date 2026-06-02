resource "aws_lb" "mqtt_nlb" {
  name               = "${var.project_name}-mqtt-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.nlb_sg.id]

  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-mqtt-nlb"
  })
}

resource "aws_lb_target_group" "mqtt_tg" {
  name        = "${var.project_name}-mqtt-tg"
  port        = 1883
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "1883"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-mqtt-tg"
  })
}

resource "aws_lb_listener" "mqtt_1883" {
  load_balancer_arn = aws_lb.mqtt_nlb.arn
  port              = 1883
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mqtt_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "core_attachment" {
  target_group_arn = aws_lb_target_group.mqtt_tg.arn
  target_id        = aws_instance.emqx_core.id
  port             = 1883
}

resource "aws_launch_template" "emqx_replicant_lt" {
  name_prefix   = "${var.project_name}-replicant-"
  image_id      = data.aws_ami.ubuntu_2204.id
  instance_type = var.replicant_instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.emqx_nodes_sg.id]

  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl gnupg apt-transport-https ca-certificates lsb-release

    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    CORE_IP="${aws_instance.emqx_core.private_ip}"

    curl -fsSL https://assets.emqx.com/scripts/install-emqx-deb.sh | bash
    apt-get update -y
    apt-get install -y emqx

    cat >> /etc/emqx/emqx.conf <<EOF
node {
  name = "emqx@$${PRIVATE_IP}"
  cookie = "${var.emqx_node_cookie}"
  role = replicant
}

cluster {
  discovery_strategy = static
  static {
    seeds = ["emqx@$${CORE_IP}"]
  }
}

dashboard {
  default_username = "${var.emqx_dashboard_username}"
  default_password = "${var.emqx_dashboard_password}"
}
EOF

    systemctl enable emqx
    systemctl restart emqx
    sleep 15
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.project_name}-replicant"
      Role = "emqx-replicant"
    })
  }
}

resource "aws_autoscaling_group" "emqx_replicants_asg" {
  name                = "${var.project_name}-replicants-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  min_size            = 1  # Kept at 1 as your sensor base
  max_size            = 2
  desired_capacity    = 1
  health_check_type   = "ELB"
  health_check_grace_period = 180 # Gives ample time for container download & sleep windows

  launch_template {
    id      = aws_launch_template.emqx_replicant_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.mqtt_tg.arn]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-replicant"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "replicants_target_tracking" {
  name                   = "${var.project_name}-replicants-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.emqx_replicants_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageNetworkIn"
    }

    target_value     = 1000000.0
    disable_scale_in = false
  }
}