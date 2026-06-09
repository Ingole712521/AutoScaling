data "aws_ami" "ubuntu_2204" {
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

locals {
  secrets_placeholder     = "USE_SECRETS_MANAGER"
  emqx_bootstrap_base = {
    node_cookie              = var.use_secrets_manager ? local.secrets_placeholder : var.emqx_node_cookie
    dashboard_username       = var.emqx_dashboard_username
    dashboard_password       = var.use_secrets_manager ? local.secrets_placeholder : var.emqx_dashboard_password
    mqtt_enable_authn        = var.emqx_mqtt_enable_authn
    mqtt_username            = var.emqx_mqtt_username
    mqtt_password            = var.use_secrets_manager ? local.secrets_placeholder : var.emqx_mqtt_password
    use_secrets_manager      = var.use_secrets_manager
    secrets_manager_secret_name = var.use_secrets_manager ? (
      var.secrets_manager_secret_name != "" ? var.secrets_manager_secret_name : "${var.project_name}/emqx"
    ) : ""
    aws_region               = var.aws_region
    project_name             = var.project_name
    emqx_version             = var.emqx_version
    tune_nofile              = var.emqx_tune_nofile
    tune_max_ports           = var.emqx_tune_max_ports
    tune_acceptors           = var.emqx_tune_acceptors
    tune_max_connections     = var.emqx_tune_max_connections
    tune_dist_buffer_size_kb = var.emqx_tune_dist_buffer_size_kb
    performance_tune_lib     = file("${path.module}/userdata/emqx-performance-tune.sh")
    eip_allocation_id        = aws_eip.core_eip.id
    cluster_autoclean        = var.emqx_cluster_autoclean
  }
}

resource "aws_eip" "core_eip" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-core-eip"
  })
}

resource "aws_launch_template" "emqx_core_lt" {
  name_prefix   = "${var.project_name}-core-"
  image_id      = data.aws_ami.ubuntu_2204.id
  instance_type = var.core_instance_type
  key_name      = var.key_name

  monitoring {
    enabled = true
  }

  vpc_security_group_ids = [aws_security_group.emqx_nodes_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.emqx_ec2.name
  }

  update_default_version = true

  user_data = base64gzip(templatefile("${path.module}/userdata/emqx-bootstrap.sh", merge(local.emqx_bootstrap_base, {
    node_role        = "core"
    core_instance_id = "asg"
  })))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.project_name}-core"
      Role = "emqx-core"
    })
  }
}

resource "aws_autoscaling_group" "emqx_core_asg" {
  name                      = "${var.project_name}-core-asg"
  vpc_zone_identifier       = aws_subnet.public[*].id
  min_size                  = var.core_min_size
  max_size                  = var.core_max_size
  desired_capacity          = var.core_desired_capacity
  health_check_type         = "EC2"
  health_check_grace_period = var.asg_health_check_grace_period

  launch_template {
    id      = aws_launch_template.emqx_core_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-core"
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

  default_cooldown = var.autoscaling_cooldown_sec

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = var.asg_instance_warmup_sec
    }
  }
}
