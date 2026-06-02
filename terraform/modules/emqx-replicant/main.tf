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

resource "aws_launch_template" "this" {
  name_prefix   = "${var.project_name}-replicant-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.replicant_sg_id]

  iam_instance_profile {
    name = var.instance_profile_name
  }

  user_data = base64encode(templatefile(var.replicant_userdata_template_path, {
    node_cookie        = var.node_cookie
    dashboard_username = var.dashboard_username
    dashboard_password = var.dashboard_password
    seed_nodes         = jsonencode(var.core_seed_hosts)
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.project_name}-replicant"
      Role = "emqx-replicant"
    })
  }
}

resource "aws_autoscaling_group" "this" {
  name                      = "${var.project_name}-replicants-asg"
  vpc_zone_identifier       = var.private_subnet_ids
  min_size                  = 1
  desired_capacity          = 1
  max_size                  = 4
  health_check_type         = "ELB"
  health_check_grace_period = 180
  target_group_arns         = var.target_group_arns

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-replicant"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
