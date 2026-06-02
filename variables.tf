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

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Workload    = "emqx"
  }
}
