output "emqx_core_public_ip" {
  description = "Static public IP of EMQX core instance for dashboard management."
  value       = aws_eip.core_eip.public_ip
}

output "mqtt_nlb_dns_name" {
  description = "NLB DNS endpoint for MQTT client connections on port 1883."
  value       = aws_lb.mqtt_nlb.dns_name
}
