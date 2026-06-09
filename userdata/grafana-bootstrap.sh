#!/usr/bin/env bash
# Grafana + CloudWatch dashboards for EMQX cluster CPU/memory (dynamic ASG instances).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

AWS_REGION="${aws_region}"
PROJECT_NAME="${project_name}"
USE_SECRETS_MANAGER="${use_secrets_manager}"
SECRETS_MANAGER_SECRET_NAME="${secrets_manager_secret_name}"
GRAFANA_ADMIN_USER="${grafana_admin_username}"
GRAFANA_ADMIN_PASSWORD="${grafana_admin_password}"
CORE_ASG_NAME="${core_asg_name}"
REPLICANT_ASG_NAME="${replicant_asg_name}"
NLB_ARN_SUFFIX="${nlb_arn_suffix}"
LOG="/var/log/grafana-bootstrap.log"

log() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }

load_grafana_credentials() {
  if [[ "$USE_SECRETS_MANAGER" != "true" ]]; then
    return 0
  fi
  if [[ "$GRAFANA_ADMIN_PASSWORD" != "USE_SECRETS_MANAGER" ]]; then
    return 0
  fi

  log "Loading Grafana credentials from Secrets Manager ($SECRETS_MANAGER_SECRET_NAME)"
  local secret_json
  secret_json="$(aws secretsmanager get-secret-value \
    --region "$AWS_REGION" \
    --secret-id "$SECRETS_MANAGER_SECRET_NAME" \
    --query SecretString \
    --output text)"

  GRAFANA_ADMIN_USER="$(jq -r '.admin_username // "admin"' <<< "$secret_json")"
  GRAFANA_ADMIN_PASSWORD="$(jq -r '.admin_password // empty' <<< "$secret_json")"

  if [[ -z "$GRAFANA_ADMIN_PASSWORD" ]]; then
    echo "Grafana secret missing admin_password" >&2
    exit 1
  fi
}

install_grafana() {
  log "Installing Grafana"
  apt-get update -y
  apt-get install -y apt-transport-https software-properties-common wget curl jq awscli

  install -d -m 0755 /etc/apt/keyrings
  wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
  chmod 0644 /etc/apt/keyrings/grafana.gpg
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
    > /etc/apt/sources.list.d/grafana.list

  apt-get update -y
  apt-get install -y grafana
}

configure_grafana() {
  log "Configuring Grafana admin + CloudWatch datasource"
  install -d -m 0755 /etc/grafana/provisioning/datasources
  install -d -m 0755 /etc/grafana/provisioning/dashboards/emqx

  {
    echo "GF_SERVER_HTTP_ADDR=0.0.0.0"
    echo "GF_SERVER_HTTP_PORT=3000"
    echo "GF_SECURITY_ADMIN_USER=$${GRAFANA_ADMIN_USER}"
    printf "GF_SECURITY_ADMIN_PASSWORD=%q\n" "$GRAFANA_ADMIN_PASSWORD"
    echo "GF_USERS_ALLOW_SIGN_UP=false"
    echo "GF_AUTH_ANONYMOUS_ENABLED=false"
  } > /etc/default/grafana-server
  chmod 0640 /etc/default/grafana-server

  cat > /etc/grafana/provisioning/datasources/cloudwatch.yaml <<EOF
apiVersion: 1
datasources:
  - name: CloudWatch
    type: cloudwatch
    uid: cloudwatch
    access: proxy
    isDefault: true
    jsonData:
      authType: default
      defaultRegion: $${AWS_REGION}
    editable: false
EOF

  cat > /etc/grafana/provisioning/dashboards/provider.yaml <<EOF
apiVersion: 1
providers:
  - name: emqx
    orgId: 1
    folder: EMQX
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards/emqx
EOF

  cat > /etc/grafana/provisioning/dashboards/emqx/emqx-cluster.json <<'DASHBOARD_EOF'
${dashboard_json}
DASHBOARD_EOF

  chown -R grafana:grafana /etc/grafana/provisioning
}

start_grafana() {
  log "Starting Grafana"
  systemctl daemon-reload
  systemctl enable grafana-server
  systemctl restart grafana-server

  for _ in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:3000/api/health" >/dev/null 2>&1; then
      log "Grafana is healthy on :3000"
      return 0
    fi
    sleep 2
  done
  systemctl status grafana-server --no-pager || true
  journalctl -u grafana-server --no-pager -n 40 || true
  exit 1
}

main() {
  : > "$LOG"
  log "Grafana bootstrap started (project=$${PROJECT_NAME})"
  load_grafana_credentials
  install_grafana
  configure_grafana
  start_grafana
  log "Grafana READY — login user=$${GRAFANA_ADMIN_USER}"
}

main "$@"
