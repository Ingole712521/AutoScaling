#!/bin/bash
# EMQX 5.8.x bootstrap for AWS EC2 (core or replicant).
# DEB layout: /etc/emqx/emqx.conf, overrides via /etc/emqx/terraform.env
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

NODE_ROLE="${node_role}"
NODE_COOKIE="${node_cookie}"
DASHBOARD_USERNAME="${dashboard_username}"
DASHBOARD_PASSWORD="${dashboard_password}"
AWS_REGION="${aws_region}"
PROJECT_NAME="${project_name}"
CORE_INSTANCE_ID="${core_instance_id}"
SSM_CORE_PARAM="/${project_name}/core-private-ip"
SSM_SEEDS_PARAM="/${project_name}/cluster-seeds"
EMQX_VERSION="${emqx_version}"
EMQX_ETC="/etc/emqx"
EMQX_CONF="/etc/emqx/emqx.conf"
EMQX_ENV_FILE="/etc/emqx/terraform.env"
SYSTEMD_DROPIN="/etc/systemd/system/emqx.service.d"
LOG="/var/log/emqx-bootstrap.log"
OK_MARKER="/var/log/emqx-bootstrap.ok"

log() {
  echo "[$(date -Is)] $*" | tee -a "$LOG"
}

fail() {
  log "ERROR: $*"
  systemctl status emqx --no-pager || true
  journalctl -u emqx --no-pager -n 80 || true
  if [[ -f "$EMQX_CONF" ]]; then
    log "--- tail $EMQX_CONF ---"
    tail -n 40 "$EMQX_CONF" | tee -a "$LOG" || true
  fi
  exit 1
}

install_packages() {
  log "STEP 1/8: Installing system packages"
  apt-get update -y
  apt-get install -y curl gnupg apt-transport-https ca-certificates lsb-release awscli netcat-openbsd
}

install_emqx() {
  log "STEP 2/8: Installing EMQX $EMQX_VERSION (DEB -> $EMQX_ETC)"
  curl -fsSL https://assets.emqx.com/scripts/install-emqx-deb.sh | bash
  apt-get update -y

  if apt-cache madison emqx | grep -q "$EMQX_VERSION"; then
    apt-get install -y "emqx=$EMQX_VERSION*" || apt-get install -y emqx
  else
    apt-get install -y emqx
  fi

  if [[ ! -f "$EMQX_CONF" ]]; then
    fail "$EMQX_CONF not found after package install"
  fi

  log "EMQX installed under $EMQX_ETC"
  log "Config files: $(ls -1 "$EMQX_ETC" | tr '\n' ' ')"
}

get_private_ip() {
  hostname -I | awk '{print $1}'
}

read_core_ip_from_ssm() {
  aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_CORE_PARAM" \
    --query "Parameter.Value" \
    --output text
}

read_seeds_from_ssm() {
  aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_SEEDS_PARAM" \
    --query "Parameter.Value" \
    --output text
}

wait_for_core() {
  local core_ip="$1"
  log "STEP 3/8: Waiting for core node $core_ip (ports 5369/4370)"
  for attempt in $(seq 1 90); do
    if nc -z "$core_ip" 5369 2>/dev/null || nc -z "$core_ip" 4370 2>/dev/null; then
      log "Core node is reachable on attempt $attempt"
      return 0
    fi
    log "Core not ready yet (attempt $attempt/90)"
    sleep 10
  done
  fail "Timed out waiting for core node $core_ip"
}

write_emqx_env() {
  local private_ip="$1"
  local seeds_hocon="$2"

  log "STEP 4/8: Writing EMQX 5.8 overrides to $EMQX_ENV_FILE"

  install -d "$SYSTEMD_DROPIN"

  cat > "$EMQX_ENV_FILE" <<EOF
EMQX_NODE__NAME="emqx@$private_ip"
EMQX_NODE__COOKIE="$NODE_COOKIE"
EMQX_CLUSTER__DISCOVERY_STRATEGY=static
EMQX_CLUSTER__STATIC__SEEDS=$seeds_hocon
EMQX_DASHBOARD__DEFAULT_USERNAME="$DASHBOARD_USERNAME"
EMQX_DASHBOARD__DEFAULT_PASSWORD="$DASHBOARD_PASSWORD"
EMQX_DASHBOARD__LISTENERS__HTTP__BIND=18083
EMQX_LISTENERS__TCP__DEFAULT__BIND=0.0.0.0:1883
EOF

  cat > "$SYSTEMD_DROPIN/terraform.conf" <<'EOF'
[Service]
EnvironmentFile=-/etc/emqx/terraform.env
EOF

  chmod 600 "$EMQX_ENV_FILE"
  chmod 644 "$SYSTEMD_DROPIN/terraform.conf"
}

start_emqx() {
  log "STEP 5/8: Starting EMQX via systemd"
  systemctl daemon-reload
  systemctl enable emqx
  systemctl restart emqx
}

wait_for_ports() {
  local require_dashboard="$1"
  log "STEP 6/8: Waiting for EMQX listeners"

  for attempt in $(seq 1 60); do
    local mqtt_up=0
    local dash_up=0

    if ss -tln | grep -q ':1883'; then
      mqtt_up=1
    fi

    if ss -tln | grep -q ':18083'; then
      dash_up=1
    fi

    if [[ "$require_dashboard" == "true" ]]; then
      if [[ "$mqtt_up" -eq 1 && "$dash_up" -eq 1 ]]; then
        log "Ports open: 1883 and 18083"
        return 0
      fi
    elif [[ "$mqtt_up" -eq 1 ]]; then
      log "Port open: 1883"
      return 0
    fi

    log "Waiting for ports (attempt $attempt/60)"
    sleep 10
  done

  fail "Timed out waiting for EMQX ports"
}

validate_emqx_service() {
  log "STEP 7/8: Validating EMQX service"
  if ! /usr/bin/emqx ctl status 2>&1 | tee -a "$LOG" | grep -qi "is running"; then
    fail "emqx ctl status reports service is not running"
  fi
  log "EMQX service is running"
}

validate_cluster() {
  log "STEP 8/8: Validating cluster membership"
  local status_output
  status_output="$(/usr/bin/emqx ctl cluster status 2>&1 | tee -a "$LOG")"

  if [[ "$NODE_ROLE" == "core" ]]; then
    if grep -qE "running_nodes|running_nodes =>" <<< "$status_output"; then
      log "Core cluster status OK"
      return 0
    fi
    log "WARN: Core cluster status format unexpected; continuing"
    return 0
  fi

  for attempt in $(seq 1 30); do
    status_output="$(/usr/bin/emqx ctl cluster status 2>&1)"
    echo "$status_output" | tee -a "$LOG"

    if grep -q "emqx@$PRIVATE_IP" <<< "$status_output"; then
      local node_lines
      node_lines="$(grep -c "emqx@" <<< "$status_output" || true)"
      if [[ "$node_lines" -ge 2 ]]; then
        log "Replicant joined cluster ($node_lines nodes visible)"
        return 0
      fi
    fi

    log "Cluster join not confirmed yet (attempt $attempt/30)"
    sleep 10
  done

  fail "Replicant did not join cluster"
}

main() {
  : > "$LOG"
  rm -f "$OK_MARKER"

  log "Bootstrap started (role=$NODE_ROLE, EMQX $EMQX_VERSION, core=$CORE_INSTANCE_ID)"
  install_packages
  install_emqx

  PRIVATE_IP="$(get_private_ip)"
  log "Private IP: $PRIVATE_IP"

  if [[ "$NODE_ROLE" == "core" ]]; then
    SEEDS="[emqx@$PRIVATE_IP]"
    write_emqx_env "$PRIVATE_IP" "$SEEDS"
    start_emqx
    wait_for_ports "true"
    validate_emqx_service
    validate_cluster
  else
    CORE_IP="$(read_core_ip_from_ssm)"
    SEEDS="$(read_seeds_from_ssm)"
    log "Core IP from SSM: $CORE_IP"
    log "Cluster seeds from SSM: $SEEDS"

    wait_for_core "$CORE_IP"
    write_emqx_env "$PRIVATE_IP" "$SEEDS"
    start_emqx
    wait_for_ports "false"
    validate_emqx_service
    validate_cluster
  fi

  date -Is > "$OK_MARKER"
  log "READY: Bootstrap complete for role=$NODE_ROLE"
}

main "$@"
