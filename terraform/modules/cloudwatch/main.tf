resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.project_name}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "Replicant CPU Utilization"
          view    = "timeSeries"
          region  = "ap-south-1"
          stacked = false
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]
          ]
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "NLB Traffic"
          view    = "timeSeries"
          region  = "ap-south-1"
          stacked = false
          metrics = [
            ["AWS/NetworkELB", "ActiveFlowCount", "LoadBalancer", var.nlb_arn_suffix],
            ["AWS/NetworkELB", "NewFlowCount", "LoadBalancer", var.nlb_arn_suffix],
            ["AWS/NetworkELB", "ProcessedBytes", "LoadBalancer", var.nlb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "Auto Scaling Capacity"
          region = "ap-south-1"
          metrics = [
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.asg_name],
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", var.asg_name]
          ]
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "Memory (CWAgent)"
          region = "ap-south-1"
          metrics = [
            ["CWAgent", "mem_used_percent", "AutoScalingGroupName", var.asg_name]
          ]
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "nlb_unhealthy" {
  alarm_name          = "${var.project_name}-nlb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Triggers if replicant targets are unhealthy"

  dimensions = {
    LoadBalancer = var.nlb_arn_suffix
    TargetGroup  = var.mqtt_target_group_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "asg_failure" {
  alarm_name          = "${var.project_name}-asg-inservice-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "ASG in-service instance count is too low"

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}
