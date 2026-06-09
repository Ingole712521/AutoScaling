output "emqx_core_public_ip" {
  description = "Static public IP of EMQX core instance for dashboard management."
  value       = aws_eip.core_eip.public_ip
}

output "core_asg_name" {
  description = "Auto Scaling Group name for EMQX core nodes."
  value       = aws_autoscaling_group.emqx_core_asg.name
}

output "emqx_core_instance_id" {
  description = "Legacy output — core runs in an ASG; use core_asg_name or EIP for ops."
  value       = "asg:${aws_autoscaling_group.emqx_core_asg.name}"
}

output "mqtt_nlb_dns_name" {
  description = "NLB DNS endpoint for MQTT client connections on port 1883."
  value       = aws_lb.mqtt_nlb.dns_name
}

output "emqx_dashboard_url" {
  description = "EMQX web dashboard URL (core node)."
  value       = "http://${aws_eip.core_eip.public_ip}:18083"
}

output "mqtt_broker_url" {
  description = "MQTT broker endpoint for clients."
  value       = "tcp://${aws_lb.mqtt_nlb.dns_name}:1883"
}

output "mqtt_auth_enabled" {
  description = "Whether MQTT username/password authentication is required."
  value       = var.emqx_mqtt_enable_authn
}

output "mqtt_auth_username" {
  description = "MQTT username for built-in database authentication."
  value       = var.emqx_mqtt_enable_authn ? var.emqx_mqtt_username : null
}

output "use_secrets_manager" {
  description = "Whether EMQX credentials are stored in AWS Secrets Manager."
  value       = var.use_secrets_manager
}

output "secrets_manager_secret_name" {
  description = "AWS Secrets Manager secret name for EMQX credentials."
  value       = var.use_secrets_manager ? aws_secretsmanager_secret.emqx[0].name : null
}

output "secrets_manager_secret_arn" {
  description = "AWS Secrets Manager secret ARN for EMQX credentials."
  value       = var.use_secrets_manager ? aws_secretsmanager_secret.emqx[0].arn : null
}

output "mqtt_tls_broker_url" {
  description = "MQTT over TLS endpoint (NLB terminates TLS with ACM). Empty when TLS is disabled."
  value       = var.enable_mqtt_tls ? "ssl://${aws_lb.mqtt_nlb.dns_name}:8883" : ""
}

output "mqtt_tls_enabled" {
  description = "Whether MQTT TLS listener on port 8883 is enabled."
  value       = var.enable_mqtt_tls
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN used by the NLB TLS listener."
  value       = var.enable_mqtt_tls ? var.acm_certificate_arn : null
}

output "nlb_security_group_id" {
  description = "Security group attached to the MQTT NLB."
  value       = aws_security_group.nlb_sg.id
}

output "emqx_nodes_security_group_id" {
  description = "Security group for EMQX core and replicant EC2 instances."
  value       = aws_security_group.emqx_nodes_sg.id
}

output "replicant_asg_name" {
  description = "Auto Scaling Group name for replicant nodes."
  value       = aws_autoscaling_group.emqx_replicants_asg.name
}

output "access_summary" {
  description = "Quick reference for URLs, ports, and firewall rules after deploy."
  value = {
    dashboard_url          = "http://${aws_eip.core_eip.public_ip}:18083"
    mqtt_nlb               = "${aws_lb.mqtt_nlb.dns_name}:1883"
    core_public_ip         = aws_eip.core_eip.public_ip
    dashboard_port         = 18083
    mqtt_port              = 1883
    dashboard_allowed_cidr = var.dashboard_allowed_cidr
    ssh_allowed_cidr       = var.ssh_allowed_cidr
    autoscaling            = "Core ASG: CPU > ${var.core_scale_out_cpu_threshold}% (+1) / < ${var.core_scale_in_cpu_threshold}% (-1), min=${var.core_min_size} max=${var.core_max_size}; Replicants: NLB/network/CPU scale-out, CPU scale-in; min=${var.replicant_min_size} max=${var.replicant_max_size}"
    emqx_version           = var.emqx_version
    performance_tuning     = "Applied at bootstrap per docs.emqx.com/performance/tune (sysctl, limits, EMQX listener/session caps)"
    tune_nofile            = var.emqx_tune_nofile
    tune_max_connections   = var.emqx_tune_max_connections
    bootstrap_log          = "/var/log/emqx-bootstrap.log on each instance"
    config_method          = "EMQX 5.8 env overrides via /etc/emqx/terraform.env + systemd drop-in"
  }
}

output "verification_commands" {
  description = "Post-deploy verification (no SSH required)."
  value = {
    dashboard_port_test = "pwsh -Command \"Test-TcpPortOpen -HostName ${aws_eip.core_eip.public_ip} -Port 18083\" (dot-source scripts/lib/PlatformHelpers.ps1 first)"
    mqtt_port_test      = "pwsh -Command \"Test-TcpPortOpen -HostName ${aws_lb.mqtt_nlb.dns_name} -Port 1883\" (dot-source scripts/lib/PlatformHelpers.ps1 first)"
    watch_bootstrap     = "pwsh -File scripts/watch_bootstrap.ps1"
    verify_all          = "pwsh -File scripts/verify_deployment.ps1"
    dashboard_url       = "http://${aws_eip.core_eip.public_ip}:18083"
  }
}
