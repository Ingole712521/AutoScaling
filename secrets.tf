resource "aws_secretsmanager_secret" "emqx" {
  count = var.use_secrets_manager ? 1 : 0

  name        = var.secrets_manager_secret_name != "" ? var.secrets_manager_secret_name : "${var.project_name}/emqx"
  description = "EMQX cluster credentials (Erlang cookie, dashboard, MQTT auth)"

  tags = merge(var.tags, {
    Name = "${var.project_name}-emqx-secrets"
  })
}

resource "aws_secretsmanager_secret_version" "emqx" {
  count = var.use_secrets_manager ? 1 : 0

  secret_id = aws_secretsmanager_secret.emqx[0].id
  secret_string = jsonencode({
    node_cookie          = var.emqx_node_cookie
    dashboard_username   = var.emqx_dashboard_username
    dashboard_password   = var.emqx_dashboard_password
    mqtt_username        = var.emqx_mqtt_username
    mqtt_password        = var.emqx_mqtt_password
    mqtt_enable_authn    = var.emqx_mqtt_enable_authn
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "grafana" {
  count = var.enable_grafana && var.use_secrets_manager ? 1 : 0

  name        = var.grafana_secrets_manager_secret_name != "" ? var.grafana_secrets_manager_secret_name : "${var.project_name}/grafana"
  description = "Grafana admin credentials"

  tags = merge(var.tags, {
    Name = "${var.project_name}-grafana-secrets"
  })
}

resource "aws_secretsmanager_secret_version" "grafana" {
  count = var.enable_grafana && var.use_secrets_manager ? 1 : 0

  secret_id = aws_secretsmanager_secret.grafana[0].id
  secret_string = jsonencode({
    admin_username = var.grafana_admin_username
    admin_password = var.grafana_admin_password
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
