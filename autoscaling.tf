# Demo autoscaling: step scaling (+1/-1) so bootstrap traffic cannot jump to max in one action.
# Network scale-out is primary; CPU is backup. Scale-in uses CPU only.

locals {
  # CloudWatch NetworkIn uses bytes per 60s period; target variable is bytes/sec.
  scale_out_network_alarm_threshold = var.scale_out_network_target_bytes * 60
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
  cooldown               = var.autoscaling_cooldown_sec
}

resource "aws_cloudwatch_metric_alarm" "replicants_high_network" {
  alarm_name          = "${var.project_name}-replicants-high-network"
  alarm_description   = "Demo scale-out (+1) when ASG network in exceeds threshold for sustained periods"
  namespace           = "AWS/EC2"
  metric_name         = "NetworkIn"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = var.scale_out_network_evaluation_periods
  threshold           = local.scale_out_network_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_autoscaling_policy.replicants_scale_out_network.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.emqx_replicants_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "replicants_high_cpu" {
  alarm_name          = "${var.project_name}-replicants-high-cpu"
  alarm_description   = "Demo backup scale-out (+1) when ASG average CPU exceeds threshold"
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
  alarm_description   = "Demo scale-in (-1) when ASG average CPU is below threshold"
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
