variable "project_name" { type = string }
variable "asg_name" { type = string }
variable "min_capacity" { type = number }
variable "max_capacity" { type = number }
variable "scale_out_cpu_threshold" { type = number }
variable "scale_in_cpu_threshold" { type = number }
