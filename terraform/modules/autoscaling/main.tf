locals {
  scale_out_network_alarm_threshold = var.scale_out_network_bytes_per_sec * 60
}

resource "aws_autoscaling_policy" "scale_out_nlb" {
  count                  = var.nlb_arn_suffix != "" ? 1 : 0
  name                   = "${var.project_name}-scale-out-nlb"
  autoscaling_group_name = var.asg_name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = var.cooldown_sec
}

resource "aws_autoscaling_policy" "scale_out_network" {
  name                   = "${var.project_name}-scale-out-network"
  autoscaling_group_name = var.asg_name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = var.cooldown_sec
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project_name}-scale-in"
  autoscaling_group_name = var.asg_name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = var.scale_in_cooldown_sec
}

resource "aws_cloudwatch_metric_alarm" "high_nlb_traffic" {
  count               = var.nlb_arn_suffix != "" ? 1 : 0
  alarm_name          = "${var.project_name}-replicant-high-nlb-traffic"
  alarm_description   = "Scale out when NLB processed bytes exceed threshold"
  namespace           = "AWS/NetworkELB"
  metric_name         = "ProcessedBytes"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = local.scale_out_network_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_out_nlb[0].arn]

  dimensions = {
    LoadBalancer = var.nlb_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "high_network" {
  alarm_name          = "${var.project_name}-replicant-high-network"
  alarm_description   = "Scale out when any replicant NetworkIn exceeds threshold"
  namespace           = "AWS/EC2"
  metric_name         = "NetworkIn"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = local.scale_out_network_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_out_network.arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.project_name}-replicant-low-cpu"
  alarm_description   = "Scale in when ASG average CPU stays below threshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = var.scale_in_metric_period_sec
  evaluation_periods  = var.scale_in_evaluation_periods
  threshold           = var.scale_in_cpu_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}
