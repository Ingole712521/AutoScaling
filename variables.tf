variable "aws_region" {
  description = "AWS region for EMQX deployment."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project/name prefix for all resources."
  type        = string
  default     = "emqx-prod"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs for 2 public subnets in different AZs."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Two availability zones for high availability."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "core_instance_type" {
  description = "EC2 instance type for permanent EMQX core."
  type        = string
  default     = "t3.small"
}

variable "replicant_instance_type" {
  description = "EC2 instance type for auto-scaled EMQX replicants."
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access."
  type        = string
  default     = null
}

variable "dashboard_allowed_cidr" {
  description = "CIDR allowed to access EMQX dashboard on port 18083."
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_mqtt_tls" {
  description = "Enable MQTT over TLS on NLB port 8883 with ACM certificate termination."
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for the NLB TLS listener (:8883). Required when enable_mqtt_tls is true. Certificate must be issued in the same region as the NLB."
  type        = string
  default     = null

  validation {
    condition     = var.enable_mqtt_tls == false || (var.acm_certificate_arn != null && var.acm_certificate_arn != "")
    error_message = "acm_certificate_arn is required when enable_mqtt_tls is true."
  }
}

variable "mqtt_tls_ssl_policy" {
  description = "AWS SSL policy for the NLB TLS listener on port 8883."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to access SSH on port 22."
  type        = string
  default     = "0.0.0.0/0"
}

variable "use_secrets_manager" {
  description = "Store EMQX credentials in AWS Secrets Manager; EC2 bootstrap and scripts read from there (not user_data)."
  type        = bool
  default     = true
}

variable "secrets_manager_secret_name" {
  description = "Secrets Manager secret name for EMQX credentials. Default: {project_name}/emqx"
  type        = string
  default     = ""
}

variable "emqx_node_cookie" {
  description = "Shared Erlang cookie for EMQX cluster nodes. Written to Secrets Manager when use_secrets_manager=true."
  type        = string
  sensitive   = true
}

variable "emqx_dashboard_username" {
  description = "Dashboard admin username."
  type        = string
  default     = "admin"
}

variable "emqx_dashboard_password" {
  description = "Dashboard admin password."
  type        = string
  sensitive   = true
}

variable "emqx_mqtt_enable_authn" {
  description = "Require username/password for MQTT connections on port 1883."
  type        = bool
  default     = true
}

variable "emqx_mqtt_username" {
  description = "MQTT username for built-in database authentication."
  type        = string
  default     = "mqtt_user"
}

variable "emqx_mqtt_password" {
  description = "MQTT password for built-in database authentication."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.emqx_mqtt_enable_authn ? length(var.emqx_mqtt_password) > 0 : true
    error_message = "emqx_mqtt_password is required when emqx_mqtt_enable_authn is true (initial Secrets Manager value or user_data)."
  }
}

variable "emqx_version" {
  description = "EMQX DEB package version to install (5.8.x)."
  type        = string
  default     = "5.8.9"
}

variable "emqx_tune_nofile" {
  description = "Open file descriptor limit for OS + EMQX (EMQX performance tuning docs)."
  type        = number
  default     = 2097152
}

variable "emqx_tune_max_ports" {
  description = "Erlang VM node.max_ports (EMQX performance tuning docs)."
  type        = number
  default     = 2097152
}

variable "emqx_tune_acceptors" {
  description = "MQTT TCP listener acceptor pool size."
  type        = number
  default     = 64
}

variable "emqx_tune_max_connections" {
  description = "MQTT TCP listener max_connections cap."
  type        = number
  default     = 1024000
}

variable "emqx_tune_dist_buffer_size_kb" {
  description = "Core node Erlang distribution buffer size in KB (node.dist_buffer_size)."
  type        = number
  default     = 2097151
}

variable "core_min_size" {
  description = "Minimum EMQX core nodes in the core ASG."
  type        = number
  default     = 1
}

variable "core_desired_capacity" {
  description = "Desired EMQX core nodes in the core ASG."
  type        = number
  default     = 1
}

variable "core_max_size" {
  description = "Maximum EMQX core nodes in the core ASG."
  type        = number
  default     = 2
}

variable "core_scale_out_cpu_threshold" {
  description = "Scale out (+1) core ASG when average CPU exceeds this percent."
  type        = number
  default     = 20
}

variable "core_scale_in_cpu_threshold" {
  description = "Scale in (-1) core ASG when average CPU stays below this percent."
  type        = number
  default     = 5
}

variable "replicant_min_size" {
  description = "Minimum replicant nodes in ASG."
  type        = number
  default     = 1
}

variable "replicant_desired_capacity" {
  description = "Desired replicant nodes in ASG."
  type        = number
  default     = 1
}

variable "replicant_max_size" {
  description = "Maximum replicant nodes in ASG."
  type        = number
  default     = 4
}

variable "scale_out_network_target_bytes" {
  description = "Scale out (+1) when NLB/ASG network exceeds this value (bytes/sec). 5000 ~= 300 KB per 60s CloudWatch period."
  type        = number
  default     = 5000
}

variable "scale_out_cpu_threshold" {
  description = "Backup scale-out when ASG average CPU exceeds this percent (MQTT load on t3.small)."
  type        = number
  default     = 25
}

variable "scale_out_network_evaluation_periods" {
  description = "Consecutive 60s periods network must exceed threshold before scale-out. Use 2+ to ignore brief bootstrap spikes."
  type        = number
  default     = 2
}

variable "asg_health_check_grace_period" {
  description = "Seconds before ASG health checks affect new instances (must cover bootstrap; lower = faster NLB/ASG visibility)."
  type        = number
  default     = 300
}

variable "asg_instance_warmup_sec" {
  description = "Instance warmup for ASG rolling refresh (seconds)."
  type        = number
  default     = 300
}

variable "emqx_cluster_autoclean" {
  description = "Remove disconnected cluster nodes from the dashboard after this duration (e.g. 2m, 5m). Default EMQX is 24h."
  type        = string
  default     = "2m"
}

variable "autoscaling_cooldown_sec" {
  description = "Cooldown after scale-out actions (seconds)."
  type        = number
  default     = 60
}

variable "scale_in_cooldown_sec" {
  description = "Cooldown after scale-in actions. Use 0 for fastest instance removal."
  type        = number
  default     = 0
}

variable "scale_in_metric_period_sec" {
  description = "CloudWatch period for scale-in CPU alarm. Use 30 with detailed EC2 monitoring for sub-minute scale-in."
  type        = number
  default     = 30
}

variable "scale_in_evaluation_periods" {
  description = "Consecutive low-CPU periods required before scale-in. With period=30 and value=2, scale-in triggers in ~60s."
  type        = number
  default     = 2
}

variable "scale_in_cpu_threshold" {
  description = "Scale in (-1) when ASG average CPU stays below this percent for scale_in_evaluation_periods."
  type        = number
  default     = 5
}

variable "enable_grafana" {
  description = "Deploy a Grafana EC2 instance with CloudWatch dashboards for EMQX CPU/memory."
  type        = bool
  default     = true
}

variable "grafana_instance_type" {
  description = "EC2 instance type for the Grafana monitoring server."
  type        = string
  default     = "t3.small"
}

variable "grafana_allowed_cidr" {
  description = "CIDR allowed to access Grafana on port 3000. Empty = same as dashboard_allowed_cidr."
  type        = string
  default     = ""
}

variable "grafana_admin_username" {
  description = "Grafana admin username. Stored in Secrets Manager when use_secrets_manager=true."
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Stored in Secrets Manager when use_secrets_manager=true."
  type        = string
  sensitive   = true
  default     = "ChangeMe!GrafanaPassword"
}

variable "grafana_secrets_manager_secret_name" {
  description = "Secrets Manager secret name for Grafana login. Default: {project_name}/grafana"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Workload    = "emqx"
  }
}
