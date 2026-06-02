variable "project_name" { type = string }
variable "zone_name" { type = string }
variable "vpc_id" { type = string }
variable "tags" { type = map(string) }

variable "create_zone" {
  type    = bool
  default = true
}

variable "zone_id" {
  type    = string
  default = null
}

variable "core_records" {
  type    = map(string)
  default = {}
}
