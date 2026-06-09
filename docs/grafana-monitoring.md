# Grafana monitoring

Grafana runs on a dedicated EC2 instance with a **public Elastic IP** and shows CPU, memory, ASG capacity, and NLB traffic for all EMQX nodes — including instances that scale up later.

## Access

After `terraform apply` (wait ~3–5 min for bootstrap):

```bash
terraform output -raw grafana_url
# http://<GRAFANA_IP>:3000
```

**Login** (default):

| Field | Value |
|-------|--------|
| Username | `admin` (or `grafana_admin_username` in tfvars) |
| Password | From Secrets Manager or `grafana_admin_password` in tfvars |

Read password from Secrets Manager:

```bash
aws secretsmanager get-secret-value \
  --region ap-south-1 \
  --secret-id "$(terraform output -raw grafana_secret_name)" \
  --query SecretString --output text | jq -r .admin_password
```

## Dashboard

Open folder **EMQX** → **EMQX Cluster — {project_name}**

| Panel | Source |
|-------|--------|
| Core / replicant desired & in-service | `AWS/AutoScaling` |
| CPU % (ASG avg + per instance) | `AWS/EC2` `CPUUtilization` |
| Memory % per instance | `CWAgent` `mem_used_percent` (CloudWatch Agent on EMQX nodes) |
| NLB flows & bytes | `AWS/NetworkELB` |

New scaled instances appear automatically within ~1–2 minutes (no dashboard edits needed).

## Architecture

```
EMQX nodes (core + replicants ASG)
  ├─ EC2 detailed monitoring → CPUUtilization
  └─ CloudWatch Agent → mem_used_percent
           ↓
     Amazon CloudWatch
           ↓
Grafana EC2 (public EIP :3000) — IAM role read-only
```

## Configuration

`terraform.tfvars`:

```hcl
enable_grafana         = true
grafana_admin_username = "admin"
grafana_admin_password = "ChangeMe!GrafanaPassword"
# grafana_allowed_cidr = "0.0.0.0/0"  # defaults to dashboard_allowed_cidr
```

Disable Grafana:

```hcl
enable_grafana = false
```

## Rotate Grafana password

1. Update `grafana_admin_password` in `terraform.tfvars`
2. Sync to Secrets Manager:

```bash
aws secretsmanager put-secret-value \
  --region ap-south-1 \
  --secret-id "$(terraform output -raw grafana_secret_name)" \
  --secret-string "$(jq -n --arg u admin --arg p 'NewPassword' '{admin_username:$u,admin_password:$p}')"
```

3. Re-run Grafana bootstrap or SSM: update `/etc/default/grafana-server` and `systemctl restart grafana-server`

## Existing EMQX nodes

CloudWatch Agent for memory is installed on **new** boots via `emqx-bootstrap.sh`. For running nodes without the agent:

- Run an **instance refresh** on core and replicant ASGs, or
- Reboot instances so bootstrap re-runs (if user_data runs on reboot — typically only first boot)

Instance refresh is the recommended path after enabling Grafana on an existing stack.

## Bootstrap log

On the Grafana instance:

```bash
sudo tail -f /var/log/grafana-bootstrap.log
```
