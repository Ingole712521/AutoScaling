# Autoscaling: NLB traffic (primary) + per-instance network peak (secondary), CPU-only scale-in.
# Step +1/-1 prevents bootstrap from jumping straight to max capacity.

locals {
  # CloudWatch NetworkIn / NLB ProcessedBytes use bytes per 60s period; variable is bytes/sec.
  scale_out_network_alarm_threshold = var.scale_out_network_target_bytes * 60
}

resource "aws_autoscaling_policy" "replicants_scale_out_nlb" {
  name                   = "${var.project_name}-replicants-scale-out-nlb"
  autoscaling_group_name = aws_autoscaling_group.emqx_replicants_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = var.autoscaling_cooldown_sec
}

resource "aws_autoscaling_policy" "replicants_scale_out_network" {
  name                   = "${var.project_name}-replicants-scale-out-network"
  autoscaling_group_name = aws_autoscaling_group.emqx_replicants_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = var.autoscaling_cooldown_sec
}

resource "aws_autoscaling_policy" "replicants_scale_out_cpu" {
  name                   = "${var.project_name}-replicants-scale-out-cpu"
  autoscaling_group_name = aws_autoscaling_group.emqx_replicants_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = var.autoscaling_cooldown_sec
}

resource "aws_autoscaling_policy" "replicants_scale_in_cpu" {
  name                   = "${var.project_name}-replicants-scale-in-cpu"
  autoscaling_group_name = aws_autoscaling_group.emqx_replicants_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = var.scale_in_cooldown_sec
}

# Primary: total MQTT bytes through the NLB (not diluted when ASG grows).
resource "aws_cloudwatch_metric_alarm" "replicants_high_nlb_traffic" {
  alarm_name          = "${var.project_name}-replicants-high-nlb-traffic"
  alarm_description   = "Scale out (+1) when NLB processed bytes exceed threshold (client load via load balancer)"
  namespace           = "AWS/NetworkELB"
  metric_name         = "ProcessedBytes"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = var.scale_out_network_evaluation_periods
  threshold           = local.scale_out_network_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.replicants_scale_out_nlb.arn]

  dimensions = {
    LoadBalancer = aws_lb.mqtt_nlb.arn_suffix
  }

  depends_on = [aws_lb_listener.mqtt_1883]
}

# Secondary: hottest replicant by NetworkIn (Maximum, not Average).
resource "aws_cloudwatch_metric_alarm" "replicants_high_network" {
  alarm_name          = "${var.project_name}-replicants-high-network"
  alarm_description   = "Scale out (+1) when any replicant NetworkIn exceeds threshold (uneven NLB hash)"
  namespace           = "AWS/EC2"
  metric_name         = "NetworkIn"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = var.scale_out_network_evaluation_periods
  threshold           = local.scale_out_network_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.replicants_scale_out_network.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.emqx_replicants_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "replicants_high_cpu" {
  alarm_name          = "${var.project_name}-replicants-high-cpu"
  alarm_description   = "Backup scale-out (+1) when ASG average CPU exceeds threshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.scale_out_cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.replicants_scale_out_cpu.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.emqx_replicants_asg.name
  }
}

resource "aws_autoscaling_policy" "core_scale_out_cpu" {
  name                   = "${var.project_name}-core-scale-out-cpu"
  autoscaling_group_name = aws_autoscaling_group.emqx_core_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = var.autoscaling_cooldown_sec
}

resource "aws_autoscaling_policy" "core_scale_in_cpu" {
  name                   = "${var.project_name}-core-scale-in-cpu"
  autoscaling_group_name = aws_autoscaling_group.emqx_core_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = var.scale_in_cooldown_sec
}

resource "aws_cloudwatch_metric_alarm" "core_high_cpu" {
  alarm_name          = "${var.project_name}-core-high-cpu"
  alarm_description   = "Scale out (+1) core ASG when average CPU exceeds threshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.core_scale_out_cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.core_scale_out_cpu.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.emqx_core_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "core_low_cpu" {
  alarm_name          = "${var.project_name}-core-low-cpu"
  alarm_description   = "Scale in (-1) core ASG when average CPU stays below threshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = var.scale_in_metric_period_sec
  evaluation_periods  = var.scale_in_evaluation_periods
  threshold           = var.core_scale_in_cpu_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.core_scale_in_cpu.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.emqx_core_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "replicants_low_cpu" {
  alarm_name          = "${var.project_name}-replicants-low-cpu"
  alarm_description   = "Scale in (-1) when ASG average CPU stays below threshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = var.scale_in_metric_period_sec
  evaluation_periods  = var.scale_in_evaluation_periods
  threshold           = var.scale_in_cpu_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.replicants_scale_in_cpu.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.emqx_replicants_asg.name
  }
}
