variable "project_name" { type = string }
variable "asg_name" { type = string }
variable "nlb_arn_suffix" { type = string }
variable "mqtt_target_group_suffix" { type = string }
variable "cpu_alarm_arn" { type = string }
variable "tags" { type = map(string) }
