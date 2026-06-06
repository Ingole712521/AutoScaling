output "emqx_core_public_ip" {
  description = "Static public IP of EMQX core instance for dashboard management."
  value       = aws_eip.core_eip.public_ip
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
    autoscaling            = "Network > ${var.scale_out_network_target_bytes} B/s or CPU > ${var.scale_out_cpu_threshold}% (+1); CPU < ${var.scale_in_cpu_threshold}% (-1); min=${var.replicant_min_size} max=${var.replicant_max_size}"
    emqx_version           = var.emqx_version
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
