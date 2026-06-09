# Authentication Validation

MQTT clients must authenticate with **username and password** using EMQX **built-in database** authentication.

## Configuration

Set in `terraform.tfvars` (with `use_secrets_manager = true`, values are stored in AWS Secrets Manager and read at boot — not embedded in `user_data`):

```hcl
use_secrets_manager     = true
emqx_mqtt_enable_authn  = true
emqx_mqtt_username      = "mqtt_user"
emqx_mqtt_password      = "ChangeMe!MqttPassword"
```

See [secrets-manager.md](secrets-manager.md) for rotation (`sync_emqx_secrets.ps1`).

Bootstrap (`userdata/emqx-bootstrap.sh`) configures:

| Setting | Value |
|---------|--------|
| Listener auth | `EMQX_LISTENERS__TCP__DEFAULT__ENABLE_AUTHN=true` |
| Mechanism | `password_based` |
| Backend | `built_in_database` |
| User | Created via EMQX API on each node |

Anonymous MQTT connections are **rejected**.

### Existing clusters (without re-apply)

```bash
pwsh -File ./scripts/fix_mqtt_anonymous_ssm.ps1
```

Enables auth and creates the MQTT user on all running instances via SSM.

## Run everything in one go

```bash
pwsh -File ./scripts/run_validation_suite.ps1
```

Runs in order: `verify_deployment` → `validate_security` → `validate_authentication` (checks) → `validate_auth_scale_out` (core + replicant ASGs) → `validate_authentication` (2K load).

Skip steps:

```bash
pwsh -File ./scripts/run_validation_suite.ps1 -Skip2K          # skip 2K load (faster)
pwsh -File ./scripts/run_validation_suite.ps1 -SkipVerify    # already verified
```

## Run authentication only

```bash
pwsh -File ./scripts/validate_authentication.ps1
```

Checks only (skip 2K load):

```bash
pwsh -File ./scripts/validate_authentication.ps1 -SkipLoad
```

Custom client count:

```bash
pwsh -File ./scripts/validate_authentication.ps1 -Clients 500
```

Expected final line:

```
=== AUTHENTICATION SUMMARY: ALL CHECKS PASSED ===
```

## What is validated

| Step | Proves |
|------|--------|
| Authentication backend configured | `password_based` + `built_in_database` chain exists and is enabled |
| Username/password enabled | TCP `:1883` listener has `enable_authn=true` |
| Anonymous rejected | Connect without credentials fails |
| Invalid credentials rejected | Wrong password fails |
| Valid credentials accepted | Correct username/password connects |
| Authentication under load | Concurrent authenticated clients with metrics |

## Example metrics (2,000 clients)

After the load phase, the script prints:

| Metric | Example value |
|--------|----------------|
| Authentication Method | Username / Password |
| Concurrent Authenticated Clients | 2,000 |
| Authentication Failures | 0 |
| Success Rate | 100% |
| Authentication Latency | p50=45.2ms p95=120.1ms avg=52.3ms |

Latency is measured from TCP connect start to successful CONNACK per client.

## Authentication during scale-out

Validates that username/password auth remains stable while the replicant ASG scales out.

```bash
pwsh -File ./scripts/validate_auth_scale_out.ps1
```

**Best run when ASG `desired_capacity=1`** so the test can observe a scale-out to 2+.

### Configuration

| Step | Action |
|------|--------|
| 1 | Hold **50** authenticated conn-only clients (baseline) |
| 2 | Add **100** authenticated publish clients to trigger autoscaling |
| 3 | Wait for ASG desired capacity to increase |
| 4 | Probe **30** fresh authenticated connects (new NLB targets / nodes) |

### Validates

| Check | Pass criteria |
|-------|----------------|
| Authenticated clients active | Baseline clients connected before scale-out |
| Autoscaling event triggered | ASG desired capacity increases |
| No increase in auth failures | `auth_failures` and `disconnects` delta = 0 on held clients |
| Successful auth on new nodes | All post-scale probe connects succeed |
| Stable cluster behavior | Cluster API shows core + all replicants |

Expected final line:

```
=== AUTH SCALE-OUT SUMMARY: ALL CHECKS PASSED ===
```

Custom sizing:

```bash
pwsh -File ./scripts/validate_auth_scale_out.ps1 -BaselineClients 40 -LoadClients 120 -TargetAsgCapacity 2
```

## Requirements for 2K test

- ASG scaled to **2+ replicants** (run sustained load first or use `run_2k_demo.py`)
- Run from a machine with enough file descriptors / RAM for 2,000 MQTT clients, or use a load-gen EC2
- Credentials in `terraform.tfvars` or `MQTT_USERNAME` / `MQTT_PASSWORD` environment variables

## Dashboard updates slowly?

EMQX default `cluster.autoclean` is **24 hours**, so terminated nodes stay visible in the UI a long time. This stack sets **`emqx_cluster_autoclean = "2m"`** so dead nodes drop off quickly after scale-in.

**While scaling**, use the live API watcher (updates every 5s):

```bash
pwsh -File ./scripts/watch_cluster_nodes.ps1
```

The dashboard **Nodes** tab does not auto-refresh as fast — click **Refresh** in the browser, or use the watcher above.

**Already-running cluster** (without re-apply):

```bash
pwsh -File ./scripts/apply_cluster_fast_refresh.ps1
```

## Related

- [security-validation.md](security-validation.md) — TLS and security groups
- [secrets-manager.md](secrets-manager.md) — AWS Secrets Manager for credentials
- [COMMANDS-REFERENCE.txt](COMMANDS-REFERENCE.txt) — Section K (Secrets Manager)
