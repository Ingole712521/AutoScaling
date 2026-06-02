# Demo autoscaling: network target tracking for fast scale-out only.
# Scale-in uses CPU alarm — idle EMQX nodes sit at ~1-2% CPU, above 0.5%, and AWS
# target-tracking scale-in requires 15 consecutive minutes of low network.

resource "aws_autoscaling_policy" "replicants_network_target" {
  name                   = "${var.project_name}-replicants-network-target"
  autoscaling_group_name = aws_autoscaling_group.emqx_replicants_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageNetworkIn"
    }

    target_value     = var.scale_out_network_target_bytes
    disable_scale_in = true
  }
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
  cooldown               = var.autoscaling_cooldown_sec
}

resource "aws_cloudwatch_metric_alarm" "replicants_high_cpu" {
  alarm_name          = "${var.project_name}-replicants-high-cpu"
  alarm_description   = "Demo backup scale-out when ASG average CPU exceeds threshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.scale_out_cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_autoscaling_policy.replicants_scale_out_cpu.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.emqx_replicants_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "replicants_low_cpu" {
  alarm_name          = "${var.project_name}-replicants-low-cpu"
  alarm_description   = "Demo scale-in when ASG average CPU is below threshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.scale_in_cpu_threshold
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_autoscaling_policy.replicants_scale_in_cpu.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.emqx_replicants_asg.name
  }
}
