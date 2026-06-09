# AWS Secrets Manager

EMQX credentials are stored in **AWS Secrets Manager** by default (`use_secrets_manager = true`).

## Secret contents

| Secret | Name | Contents |
|--------|------|----------|
| EMQX | `{project_name}/emqx` | Cookie, dashboard, MQTT credentials |
| Grafana | `{project_name}/grafana` | `admin_username`, `admin_password` (when `enable_grafana=true`) |

EMQX secret example:

```json
{
  "node_cookie": "...",
  "dashboard_username": "admin",
  "dashboard_password": "...",
  "mqtt_username": "mqtt_user",
  "mqtt_password": "...",
  "mqtt_enable_authn": true
}
```

## How it is used

| Component | Behavior |
|-----------|----------|
| **Terraform** | Creates secret on `terraform apply` from `terraform.tfvars` (first time) |
| **EC2 bootstrap** | Reads secret at startup — passwords are **not** embedded in `user_data` |
| **Validation scripts** | Load credentials from Secrets Manager via AWS CLI |
| **IAM (EC2 role)** | `secretsmanager:GetSecretValue` on the cluster secret |

## Setup

1. Set secrets in `terraform.tfvars` (first apply only):

```hcl
use_secrets_manager     = true
emqx_node_cookie        = "ChangeThisCookieForProduction"
emqx_dashboard_password = "ChangeMe!StrongPassword"
emqx_mqtt_password      = "ChangeMe!MqttPassword"
```

2. Apply:

```bash
terraform apply
```

3. Scripts work without passing passwords:

```bash
pwsh -File ./scripts/run_validation_suite.ps1
```

## Rotate / update passwords

1. Edit `terraform.tfvars` with new values.
2. Sync to Secrets Manager:

```bash
pwsh -File ./scripts/sync_emqx_secrets.ps1
```

3. Replace instances (instance refresh) or reboot nodes so bootstrap re-reads secrets on new launches.

## Terraform outputs

```bash
terraform output -raw secrets_manager_secret_name
terraform output -raw secrets_manager_secret_arn
terraform output -raw use_secrets_manager
```

## Disable Secrets Manager (legacy)

```hcl
use_secrets_manager = false
```

Credentials are passed via `user_data` again (less secure).

## Local access

Your workstation needs IAM permission `secretsmanager:GetSecretValue` on the secret (same as scripts use). EC2 instances use the instance profile automatically.
