variable "project_name" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "nlb_sg_id" { type = string }
variable "replicant_sg_id" { type = string }
variable "tags" { type = map(string) }
