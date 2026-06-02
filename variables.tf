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

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to access SSH on port 22."
  type        = string
  default     = "0.0.0.0/0"
}

variable "emqx_node_cookie" {
  description = "Shared Erlang cookie for EMQX cluster nodes."
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

variable "emqx_version" {
  description = "EMQX DEB package version to install (5.8.x)."
  type        = string
  default     = "5.8.9"
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
  description = "Demo: scale replicants when ASG average network in exceeds this value (bytes/sec). MQTT load triggers this early."
  type        = number
  default     = 20000
}

variable "autoscaling_cooldown_sec" {
  description = "Cooldown between demo scale actions (seconds)."
  type        = number
  default     = 60
}

variable "scale_out_cpu_threshold" {
  description = "Backup demo scale-out CPU percent (MQTT rarely hits this; network metric is primary)."
  type        = number
  default     = 1
}

variable "scale_in_cpu_threshold" {
  description = "Demo scale-in when ASG average CPU is below this percent. Must exceed idle EMQX baseline (~1-2% with multiple nodes)."
  type        = number
  default     = 3
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
