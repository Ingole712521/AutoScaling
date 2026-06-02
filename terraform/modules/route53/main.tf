locals {
  zone_id_effective = var.create_zone ? aws_route53_zone.this[0].zone_id : var.zone_id
}

resource "aws_route53_zone" "this" {
  count = var.create_zone ? 1 : 0
  name  = var.zone_name

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.zone_name}"
  })
}

resource "aws_route53_record" "core" {
  for_each = var.core_records

  zone_id = local.zone_id_effective
  name    = "${each.key}.${var.zone_name}"
  type    = "A"
  ttl     = 60
  records = [each.value]
}
