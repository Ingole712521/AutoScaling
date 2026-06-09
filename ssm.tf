resource "aws_ssm_parameter" "core_private_ip" {
  name  = "/${var.project_name}/core-private-ip"
  type  = "String"
  value = "0.0.0.0"

  tags = merge(var.tags, {
    Name = "${var.project_name}-core-private-ip"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "cluster_seeds" {
  name  = "/${var.project_name}/cluster-seeds"
  type  = "String"
  value = "[]"

  tags = merge(var.tags, {
    Name = "${var.project_name}-cluster-seeds"
  })

  lifecycle {
    ignore_changes = [value]
  }
}
