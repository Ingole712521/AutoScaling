variable "project_name" { type = string }
variable "asg_name" { type = string }
variable "min_capacity" { type = number }
variable "max_capacity" { type = number }
variable "nlb_arn_suffix" {
  type        = string
  description = "NLB arn_suffix for ProcessedBytes alarm; empty disables NLB-based scale-out."
  default     = ""
}
variable "scale_in_cpu_threshold" { type = number }
variable "scale_out_network_bytes_per_sec" {
  type        = number
  description = "Scale out when traffic exceeds this many bytes per second."
  default     = 20480
}
variable "cooldown_sec" {
  type    = number
  default = 60
}
variable "scale_in_cooldown_sec" {
  type    = number
  default = 0
}
variable "scale_in_metric_period_sec" {
  type    = number
  default = 30
}
variable "scale_in_evaluation_periods" {
  type    = number
  default = 2
}
