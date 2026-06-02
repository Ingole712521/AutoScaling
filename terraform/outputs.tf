output "nlb_dns_name" {
  description = "NLB endpoint for MQTT clients."
  value       = module.nlb.nlb_dns_name
}

output "emqx_dashboard_urls" {
  description = "Dashboard URLs for core nodes."
  value = {
    for k, ip in module.emqx_core.private_ips : k => "http://${ip}:18083"
  }
}

output "core_private_ips" {
  description = "Core node private IPs."
  value       = module.emqx_core.private_ips
}

output "replicant_asg_name" {
  description = "Replicant Auto Scaling Group name."
  value       = module.emqx_replicant.asg_name
}

output "key_pair_name" {
  description = "Shared SSH key pair name."
  value       = module.keypair.key_name
}

output "generated_private_key_path" {
  description = "Path of generated private key file."
  value       = module.keypair.private_key_path
}
