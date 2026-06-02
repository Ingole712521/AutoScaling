output "nlb_dns_name" {
  value = aws_lb.this.dns_name
}

output "nlb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "mqtt_target_group_arn" {
  value = aws_lb_target_group.mqtt.arn
}

output "mqtt_target_group_arn_suffix" {
  value = aws_lb_target_group.mqtt.arn_suffix
}

output "mqtt_tls_target_group_arn" {
  value = aws_lb_target_group.mqtt_tls.arn
}
