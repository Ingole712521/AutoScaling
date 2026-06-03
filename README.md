# EMQX on AWS — Production Demo (Core + Replicant + NLB + Autoscaling)

End-to-end EMQX 5.8 cluster on AWS: **one core** (cluster coordination + dashboard), **auto-scaled replicants** (MQTT client traffic via NLB), step scaling **+1 / -1**, and proof scripts.

## Architecture

```
Internet
    │
    ▼
┌─────────────────┐
│  NLB :1883 TCP  │  cross-zone, flow-hash per connection
└────────┬────────┘
         │  target group (healthy = MQTT :1883)
         ▼
┌─────────────────────────────┐
│  ASG: replicants (1–4)      │  EMQX role=replicant, join via SSM seeds
│  public subnets, ELB health  │
└────────┬────────────────────┘
         │  cluster (5369/4370)
         ▼
┌─────────────────────────────┐
│  EC2 core (1 node + EIP)    │  EMQX role=core, dashboard :18083
│  publishes SSM discovery    │
└─────────────────────────────┘
```

| Component | Role |
|-----------|------|
| **Core** | Fixed node + dashboard at `http://<core-eip>:18083`; not in NLB (OSS peer node) |
| **Replicants** | ASG nodes; all MQTT via NLB (OSS peer nodes, no `node.role` in 5.8+) |
| **NLB** | Distributes TCP connections across healthy replicants |
| **SSM** | `/emqx-prod/core-private-ip` and `/emqx-prod/cluster-seeds` (core updates on boot) |

Mermaid: [`docs/architecture.md`](docs/architecture.md). Modular 3-core layout: [`terraform/`](terraform/) (separate `terraform apply`).

## Quick start (root stack — use this for scripts)

```powershell
cd D:\Nehal\Project\emqx\job
copy terraform.tfvars.example terraform.tfvars
# Edit emqx_node_cookie and emqx_dashboard_password

.\scripts\deploy_and_load_test.ps1
```

Or manual:

```powershell
terraform init
terraform apply
.\scripts\verify_deployment.ps1
.\scripts\prove_emqx_cluster.ps1
.\scripts\run_staged_load_test.ps1 -FromTerraform
```

## Autoscaling

| Action | Trigger |
|--------|---------|
| **Scale out +1** | NLB `ProcessedBytes` **or** ASG `NetworkIn` (Maximum) > 20 KB/s for **2×60s** |
| **Scale in -1** | ASG average CPU < **5%** for **2×30s** |
| **Cooldown** | 60s scale-out; 0s scale-in |
| **Bounds** | min=1, max=4 replicants |

Step scaling avoids jumping to max on `terraform apply`. The staged load test drives scale-out; the last stage (`10` clients) drives scale-in.

## Proof checklist

1. `.\scripts\verify_deployment.ps1` — ports + MQTT probe + NLB health  
2. `.\scripts\prove_emqx_cluster.ps1` — cluster API, NLB, load spread  
3. `.\scripts\run_staged_load_test.ps1 -FromTerraform` — autoscaling demo  

See [`docs/PROOF-CHECKLIST.md`](docs/PROOF-CHECKLIST.md).

## Load distribution

- Clients connect to **NLB DNS** only (security group blocks direct MQTT to instances).
- NLB uses **per-connection** flow hashing — many concurrent clients spread across replicants.
- With **1** replicant, all traffic is on one node (expected). After scale-out, re-run proof with `-LoadClients 50`.

## Project layout

| Path | Purpose |
|------|---------|
| `*.tf` (root) | Primary stack: VPC, core, NLB, ASG, autoscaling |
| `userdata/emqx-bootstrap.sh` | Core + replicant install, join, validation |
| `scripts/` | Deploy, verify, prove, load test |
| `loadtest/staged_load.py` | Staged MQTT load via NLB |
| `terraform/` | Optional modular stack (3 cores, private subnets) |

## Security notes

- MQTT on replicants: **only from NLB security group**
- Dashboard: `dashboard_allowed_cidr`
- Do not commit `terraform.tfvars` (secrets)

## Cost

Brief demo in `ap-south-1`: 1 core + 1–4 small replicants + NLB. Tear down when finished: `terraform destroy`.
