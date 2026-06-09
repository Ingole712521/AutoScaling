#!/usr/bin/env bash
# EMQX 5.8.x bootstrap for AWS EC2 (core or replicant).
# DEB layout: /etc/emqx/emqx.conf, overrides via /etc/emqx/terraform.env
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

NODE_ROLE="${node_role}"
NODE_COOKIE="${node_cookie}"
DASHBOARD_USERNAME="${dashboard_username}"
DASHBOARD_PASSWORD="${dashboard_password}"
MQTT_ENABLE_AUTHN="${mqtt_enable_authn}"
MQTT_USERNAME="${mqtt_username}"
MQTT_PASSWORD="${mqtt_password}"
USE_SECRETS_MANAGER="${use_secrets_manager}"
SECRETS_MANAGER_SECRET_NAME="${secrets_manager_secret_name}"
CLUSTER_AUTOCLEAN="${cluster_autoclean}"
AWS_REGION="${aws_region}"
PROJECT_NAME="${project_name}"
CORE_INSTANCE_ID="${core_instance_id}"
EIP_ALLOCATION_ID="${eip_allocation_id}"
SSM_CORE_PARAM="/${project_name}/core-private-ip"
SSM_SEEDS_PARAM="/${project_name}/cluster-seeds"
EMQX_VERSION="${emqx_version}"
EMQX_ETC="/etc/emqx"
EMQX_CONF="/etc/emqx/emqx.conf"
EMQX_ENV_FILE="/etc/emqx/terraform.env"
SYSTEMD_DROPIN="/etc/systemd/system/emqx.service.d"
LOG="/var/log/emqx-bootstrap.log"
OK_MARKER="/var/log/emqx-bootstrap.ok"

# Performance tuning (https://docs.emqx.com/en/emqx/latest/performance/tune.html)
EMQX_TUNE_NOFILE="${tune_nofile}"
EMQX_TUNE_MAX_PORTS="${tune_max_ports}"
EMQX_TUNE_ACCEPTORS="${tune_acceptors}"
EMQX_TUNE_MAX_CONNECTIONS="${tune_max_connections}"
EMQX_TUNE_DIST_BUFFER_SIZE_KB="${tune_dist_buffer_size_kb}"

${performance_tune_lib}

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
  log "STEP 1/11: Installing system packages"
  apt-get update -y
  apt-get install -y curl gnupg apt-transport-https ca-certificates lsb-release awscli netcat-openbsd jq
}

install_cloudwatch_agent() {
  log "STEP 2/11: Installing CloudWatch Agent (memory metrics for Grafana)"
  if dpkg -s amazon-cloudwatch-agent >/dev/null 2>&1; then
    log "CloudWatch Agent already installed"
    return 0
  fi

  wget -q -O /tmp/amazon-cloudwatch-agent.deb \
    https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  dpkg -i /tmp/amazon-cloudwatch-agent.deb
  rm -f /tmp/amazon-cloudwatch-agent.deb

  cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCFG'
{
  "metrics": {
    "append_dimensions": {
      "AutoScalingGroupName": "$${aws:AutoScalingGroupName}",
      "InstanceId": "$${aws:InstanceId}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": [
          "mem_used_percent"
        ]
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "resources": [
          "/"
        ],
        "ignore_file_system_types": [
          "tmpfs",
          "devtmpfs",
          "squashfs"
        ]
      }
    }
  }
}
CWCFG

  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s
  log "CloudWatch Agent started (mem_used_percent -> CWAgent namespace)"
}

load_credentials_from_secrets_manager() {
  if [[ "$USE_SECRETS_MANAGER" != "true" ]]; then
    return 0
  fi
  if [[ "$NODE_COOKIE" != "USE_SECRETS_MANAGER" ]]; then
    return 0
  fi

  log "Loading EMQX credentials from AWS Secrets Manager ($SECRETS_MANAGER_SECRET_NAME)"
  local secret_json
  secret_json="$(aws secretsmanager get-secret-value \
    --region "$AWS_REGION" \
    --secret-id "$SECRETS_MANAGER_SECRET_NAME" \
    --query SecretString \
    --output text)"

  NODE_COOKIE="$(jq -r '.node_cookie // empty' <<< "$secret_json")"
  DASHBOARD_USERNAME="$(jq -r '.dashboard_username // "admin"' <<< "$secret_json")"
  DASHBOARD_PASSWORD="$(jq -r '.dashboard_password // empty' <<< "$secret_json")"
  MQTT_USERNAME="$(jq -r '.mqtt_username // empty' <<< "$secret_json")"
  MQTT_PASSWORD="$(jq -r '.mqtt_password // empty' <<< "$secret_json")"
  local authn
  authn="$(jq -r '.mqtt_enable_authn // true' <<< "$secret_json")"
  if [[ "$authn" == "true" || "$authn" == "1" ]]; then
    MQTT_ENABLE_AUTHN="true"
  else
    MQTT_ENABLE_AUTHN="false"
  fi

  if [[ -z "$NODE_COOKIE" || -z "$DASHBOARD_PASSWORD" ]]; then
    fail "Secrets Manager secret missing node_cookie or dashboard_password"
  fi
  log "Credentials loaded from Secrets Manager (MQTT auth=$MQTT_ENABLE_AUTHN)"
}

apply_performance_tuning() {
  log "STEP 3/11: OS + network performance tuning (EMQX docs)"
  apply_emqx_performance_tuning "$NODE_ROLE"
}

install_emqx() {
  log "STEP 4/11: Installing EMQX $EMQX_VERSION (DEB -> $EMQX_ETC)"
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

append_seed() {
  local seeds="$1"
  local ip="$2"
  local entry="emqx@$ip"
  if grep -qF "$entry" <<< "$seeds"; then
    printf '%s' "$seeds"
    return
  fi
  if [[ "$seeds" == "[]" || -z "$seeds" ]]; then
    printf "[%s]" "$entry"
    return
  fi
  local inner="$${seeds#[}"
  inner="$${inner%]}"
  printf "[%s, %s]" "$inner" "$entry"
}

publish_primary_core_ssm() {
  local private_ip="$1"
  local seeds="$2"
  log "Publishing primary core to SSM ($SSM_CORE_PARAM, $SSM_SEEDS_PARAM)"
  aws ssm put-parameter --region "$AWS_REGION" --name "$SSM_CORE_PARAM" --value "$private_ip" --type String --overwrite
  aws ssm put-parameter --region "$AWS_REGION" --name "$SSM_SEEDS_PARAM" --value "$seeds" --type String --overwrite
}

publish_cluster_seeds() {
  local seeds="$1"
  log "Updating cluster seeds in SSM: $seeds"
  aws ssm put-parameter --region "$AWS_REGION" --name "$SSM_SEEDS_PARAM" --value "$seeds" --type String --overwrite
}

associate_core_eip() {
  if [[ "$NODE_ROLE" != "core" || -z "$EIP_ALLOCATION_ID" || "$EIP_ALLOCATION_ID" == "none" ]]; then
    return 0
  fi
  local instance_id
  instance_id="$(curl -sf http://169.254.169.254/latest/meta-data/instance-id)"
  log "Associating Elastic IP $EIP_ALLOCATION_ID to primary core $instance_id"
  aws ec2 associate-address \
    --region "$AWS_REGION" \
    --instance-id "$instance_id" \
    --allocation-id "$EIP_ALLOCATION_ID" \
    --allow-reassociation || log "EIP association skipped (may already be attached)"
}

wait_for_core() {
  local core_ip="$1"
  log "STEP 5/11: Waiting for core node $core_ip (ports 5369/4370)"
  for attempt in $(seq 1 60); do
    if nc -z "$core_ip" 5369 2>/dev/null || nc -z "$core_ip" 4370 2>/dev/null; then
      log "Core node is reachable on attempt $attempt"
      return 0
    fi
    log "Core not ready yet (attempt $attempt/60)"
    sleep 3
  done
  fail "Timed out waiting for core node $core_ip"
}

write_emqx_env() {
  local private_ip="$1"
  local seeds_hocon="$2"

  log "STEP 6/11: Writing EMQX 5.8 overrides to $EMQX_ENV_FILE"

  install -d "$SYSTEMD_DROPIN"

  # EMQX Open Source 5.8+ does not support node.role (Enterprise only).
  # Operational split: fixed core EC2 + ASG nodes behind NLB; all join one static cluster.
  local authn_flag="false"
  if [[ "$MQTT_ENABLE_AUTHN" == "true" ]]; then
    authn_flag="true"
  fi

  cat > "$EMQX_ENV_FILE" <<EOF
EMQX_NODE__NAME="emqx@$private_ip"
EMQX_NODE__COOKIE="$NODE_COOKIE"
EMQX_CLUSTER__DISCOVERY_STRATEGY=static
EMQX_CLUSTER__STATIC__SEEDS=$seeds_hocon
EMQX_CLUSTER__AUTOCLEAN=$CLUSTER_AUTOCLEAN
EMQX_CLUSTER__AUTOHEAL=true
EMQX_DASHBOARD__DEFAULT_USERNAME="$DASHBOARD_USERNAME"
EMQX_DASHBOARD__DEFAULT_PASSWORD="$DASHBOARD_PASSWORD"
EMQX_DASHBOARD__LISTENERS__HTTP__BIND=18083
EMQX_LISTENERS__TCP__DEFAULT__BIND=0.0.0.0:1883
EMQX_LISTENERS__TCP__DEFAULT__ENABLE_AUTHN=$authn_flag
EMQX_MQTT__MAX_PACKET_SIZE=1MB
EOF

  if [[ "$MQTT_ENABLE_AUTHN" == "true" ]]; then
    cat >> "$EMQX_ENV_FILE" <<EOF
EMQX_AUTHENTICATION__1__MECHANISM=password_based
EMQX_AUTHENTICATION__1__BACKEND=built_in_database
EMQX_AUTHENTICATION__1__ENABLE=true
EMQX_AUTHENTICATION__1__USER_ID_TYPE=username
EOF
  fi

  append_emqx_performance_env "$NODE_ROLE" >> "$EMQX_ENV_FILE"

  cat > "$SYSTEMD_DROPIN/terraform.conf" <<'EOF'
[Service]
EnvironmentFile=-/etc/emqx/terraform.env
EOF

  chmod 600 "$EMQX_ENV_FILE"
  chmod 644 "$SYSTEMD_DROPIN/terraform.conf"
}

start_emqx() {
  log "STEP 7/11: Starting EMQX via systemd"
  systemctl daemon-reload
  systemctl enable emqx
  systemctl restart emqx
}

wait_for_ports() {
  local require_dashboard="$1"
  log "STEP 8/11: Waiting for EMQX listeners"

  for attempt in $(seq 1 40); do
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

    log "Waiting for ports (attempt $attempt/40)"
    sleep 3
  done

  fail "Timed out waiting for EMQX ports"
}

validate_emqx_service() {
  log "STEP 9/11: Validating EMQX service"
  for attempt in $(seq 1 20); do
    if systemctl is-active --quiet emqx 2>/dev/null; then
      local status_out
      status_out="$(/usr/bin/emqx ctl status 2>&1 || true)"
      echo "$status_out" | tee -a "$LOG"
      if grep -qiE "is running|EMQX .* is running" <<< "$status_out"; then
        log "EMQX service is running (attempt $attempt)"
        return 0
      fi
    fi
    sleep 3
  done
  if systemctl is-active --quiet emqx && ss -tln | grep -q ':1883'; then
    log "EMQX active (ports up; ctl status was slow)"
    return 0
  fi
  fail "emqx service not running after validation retries"
}

count_cluster_nodes() {
  local status_output="$1"
  grep -oE 'emqx@[0-9a-zA-Z._:-]+' <<< "$status_output" | sort -u | wc -l
}

validate_cluster() {
  log "STEP 10/11: Validating cluster membership"
  local status_output
  status_output="$(/usr/bin/emqx ctl cluster status 2>&1 | tee -a "$LOG")"

  local node_count
  node_count="$(count_cluster_nodes "$status_output")"

  if [[ "$NODE_ROLE" == "core" ]]; then
    if [[ "$node_count" -ge 1 ]]; then
      log "Core cluster status OK (nodes visible: $node_count)"
      return 0
    fi
    fail "Core cluster status shows no nodes"
  fi

  for attempt in $(seq 1 45); do
    status_output="$(/usr/bin/emqx ctl cluster status 2>&1)"
    echo "$status_output" | tee -a "$LOG"

    node_count="$(count_cluster_nodes "$status_output")"
    if [[ "$node_count" -ge 2 ]] && grep -qF "emqx@$PRIVATE_IP" <<< "$status_output"; then
      log "Replicant joined cluster ($node_count unique nodes, this node listed)"
      return 0
    fi

    log "Cluster join not confirmed yet (nodes=$node_count, attempt $attempt/45)"
    sleep 4
  done

  fail "Replicant did not join cluster (expected >= 2 nodes including emqx@$PRIVATE_IP)"
}

ensure_mqtt_user() {
  if [[ "$MQTT_ENABLE_AUTHN" != "true" ]]; then
    log "MQTT authentication disabled; skipping built-in user setup"
    return 0
  fi

  log "Configuring built-in database MQTT user: $MQTT_USERNAME"
  local token
  token="$(curl -sf -X POST "http://127.0.0.1:18083/api/v5/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$DASHBOARD_USERNAME\",\"password\":\"$DASHBOARD_PASSWORD\"}" \
    | jq -r '.token // empty')"

  if [[ -z "$token" ]]; then
    fail "Dashboard login failed while creating MQTT user"
  fi

  local http_code
  http_code="$(curl -sf -o /tmp/emqx-mqtt-user.json -w "%%{http_code}" -X POST \
    "http://127.0.0.1:18083/api/v5/authentication/password_based%3Abuilt_in_database/users" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":\"$MQTT_USERNAME\",\"password\":\"$MQTT_PASSWORD\"}")"

  if [[ "$http_code" == "200" || "$http_code" == "201" || "$http_code" == "409" ]]; then
    log "MQTT user $MQTT_USERNAME ready (HTTP $http_code)"
    return 0
  fi

  fail "MQTT user creation failed (HTTP $http_code): $(cat /tmp/emqx-mqtt-user.json 2>/dev/null || true)"
}

mark_ready() {
  log "STEP 11/11: Bootstrap complete"
  date -Is > "$OK_MARKER"
  log "READY: role=$NODE_ROLE node=emqx@$PRIVATE_IP"
}

main() {
  : > "$LOG"
  rm -f "$OK_MARKER"

  log "Bootstrap started (role=$NODE_ROLE, EMQX $EMQX_VERSION)"
  install_packages
  install_cloudwatch_agent
  load_credentials_from_secrets_manager
  apply_performance_tuning
  install_emqx

  PRIVATE_IP="$(get_private_ip)"
  log "Private IP: $PRIVATE_IP"

  if [[ "$NODE_ROLE" == "core" ]]; then
    EXISTING_CORE="$(read_core_ip_from_ssm 2>/dev/null || echo "0.0.0.0")"
    EXISTING_SEEDS="$(read_seeds_from_ssm 2>/dev/null || echo "[]")"

    if [[ "$EXISTING_CORE" == "0.0.0.0" || -z "$EXISTING_CORE" || "$EXISTING_CORE" == "$PRIVATE_IP" ]]; then
      SEEDS="$(append_seed "[]" "$PRIVATE_IP")"
      publish_primary_core_ssm "$PRIVATE_IP" "$SEEDS"
      associate_core_eip
    else
      log "Secondary core joining primary at $EXISTING_CORE"
      wait_for_core "$EXISTING_CORE"
      SEEDS="$(append_seed "$EXISTING_SEEDS" "$PRIVATE_IP")"
      publish_cluster_seeds "$SEEDS"
    fi

    write_emqx_env "$PRIVATE_IP" "$SEEDS"
    start_emqx
    wait_for_ports "true"
    validate_emqx_service
    validate_cluster
    ensure_mqtt_user
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
    ensure_mqtt_user
  fi

  mark_ready
}

main "$@"
