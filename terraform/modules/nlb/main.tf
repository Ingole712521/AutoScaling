resource "aws_lb" "this" {
  name               = "${var.project_name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids
  security_groups    = [var.nlb_sg_id]

  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, { Name = "${var.project_name}-nlb" })
}

resource "aws_lb_target_group" "mqtt" {
  name        = "${var.project_name}-mqtt-1883"
  port        = 1883
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  deregistration_delay = 10

  health_check {
    protocol = "TCP"
    port     = "1883"
  }

  tags = merge(var.tags, { Name = "${var.project_name}-tg-1883" })
}

resource "aws_lb_listener" "mqtt" {
  load_balancer_arn = aws_lb.this.arn
  port              = 1883
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mqtt.arn
  }
}
