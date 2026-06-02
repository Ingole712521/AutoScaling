variable "project_name" { type = string }
variable "vpc_id" { type = string }
variable "dashboard_allowed_cidr" { type = string }
variable "ssh_allowed_cidr" { type = string }
variable "tags" { type = map(string) }
