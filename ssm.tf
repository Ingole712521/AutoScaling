resource "aws_ssm_parameter" "core_private_ip" {
  name  = "/${var.project_name}/core-private-ip"
  type  = "String"
  value = aws_instance.emqx_core.private_ip

  tags = merge(var.tags, {
    Name = "${var.project_name}-core-private-ip"
  })
}

resource "aws_ssm_parameter" "cluster_seeds" {
  name  = "/${var.project_name}/cluster-seeds"
  type  = "String"
  value = "[emqx@${aws_instance.emqx_core.private_ip}]"

  tags = merge(var.tags, {
    Name = "${var.project_name}-cluster-seeds"
  })
}
