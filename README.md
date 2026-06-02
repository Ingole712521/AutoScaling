# EMQX on AWS (Interview-Grade Demo)

Production-style EMQX 5.x cluster on AWS using Terraform modules, native EC2 installation (no Docker), Route53 private DNS discovery, Network Load Balancer, Auto Scaling, and CloudWatch observability.

## 1) Architecture Overview

- Region: `ap-south-1`
- VPC: `10.0.0.0/16`
- Public subnets: `10.0.1.0/24`, `10.0.2.0/24`
- Private subnets: `10.0.11.0/24`, `10.0.12.0/24`
- Core nodes (fixed): 3 x `t3.medium` (`emqx-core-1..3`)
- Replicant nodes (ASG): min=1, desired=1, max=4 (`t3.medium`)
- NLB listeners: `1883` and `8883` TCP
- Route53 private zone: `emqx.internal`
- SSM Session Manager and SSH enabled

Mermaid diagram: see [`docs/architecture.md`](docs/architecture.md).

## 2) AWS Services Used

- EC2
- Auto Scaling Group
- Network Load Balancer
- VPC / Subnets / NAT Gateway / Route Tables
- Route53 Private Hosted Zone
- IAM (least privilege for SSM/CWAgent/Route53 read)
- CloudWatch Dashboard + Alarms
- Systems Manager (Session Manager)

## 3) Project Structure

```text
project-root/
  terraform/
    main.tf
    providers.tf
    versions.tf
    variables.tf
    outputs.tf
    terraform.tfvars.example
    modules/
      vpc/
      security-groups/
      iam/
      route53/
      nlb/
      emqx-core/
      emqx-replicant/
      autoscaling/
      cloudwatch/
      keypair/
  userdata/
    core.sh
    replicant.sh
  frontend/
    nextjs-dashboard/
  docs/
    architecture.md
```

## 4) Deployment Steps

1. Go to project root:

```powershell
cd "d:\New folder\emqx"
```

2. Create tfvars (if not already):

```powershell
copy terraform.tfvars.example terraform.tfvars
```

3. Update at least in `terraform.tfvars`:
- `emqx_node_cookie`
- `emqx_dashboard_password`
- `dashboard_allowed_cidr` (use your public IP/32 or `0.0.0.0/0` for demo)
- `ssh_allowed_cidr`

4. **One-command deploy + dashboard + autoscaling load test:**

```powershell
.\scripts\deploy_and_load_test.ps1
```

This will:
- run `terraform apply`
- print dashboard URL, NLB, firewall, and autoscaling info
- wait until ports **18083** and **1883** are reachable
- open the dashboard in your browser
- start the load test in a **new PowerShell window** to push CPU above the threshold

Manual deploy only:

```powershell
terraform init
terraform apply
.\scripts\run_after_apply.ps1
```

## 5) How EMQX Cluster Works

- Core nodes boot first and run native EMQX service.
- Each core node has a DNS identity in `emqx.internal`.
- Replicant nodes scale via ASG and use the same seed list for join.
- Replicants serve client traffic; cores coordinate metadata/session routing.

## 6) Core vs Replicant Explanation

- **Core nodes (fixed 3):** stable control-layer for cluster metadata and coordination.
- **Replicant nodes (1-4):** client-facing data lane that scales up/down automatically.

## 7) Auto Scaling Explanation (Demo Thresholds)

- Scale out: network in > 20 KB/s **or** CPU > 1% (demo — triggers in stage 1)
- Scale in: CPU < 3% for 2 minutes (network policy is scale-out only; AWS target-tracking scale-in needs ~15 min)
- Cooldown: 60 seconds
- Never scales below 1 replicant

These are intentionally small, interview-friendly thresholds to demonstrate behavior at low cost.

## 8) Load Balancer Explanation

- NLB receives MQTT traffic on `1883` and `8883`.
- Target groups forward traffic only to replicant instances.
- Health checks use TCP on `1883`.

## 9) Demo Scenario

- Start: 5 clients -> 1 replicant
- Raise to 15 clients -> scale to 2 replicants
- Raise to 25 clients -> scale to 3 replicants
- Lower to 5 clients -> scale in to 1 replicant

Run the staged load test after `terraform apply` to drive this scenario:

```powershell
# Windows (from project root)
.\scripts\run_after_apply.ps1
```

```bash
# Linux/macOS
FROM_TERRAFORM=true ./scripts/run_staged_load_test.sh
```

Or pass the NLB DNS manually:

```powershell
.\scripts\run_staged_load_test.ps1 -MqttHost "your-nlb.elb.amazonaws.com"
```

```bash
MQTT_HOST=your-nlb.elb.amazonaws.com ./scripts/run_staged_load_test.sh
```

Default load stages (override with `LOAD_STAGES`):

| Stage | Clients | Burst | Est. throughput | Goal |
|-------|---------|-------|-----------------|------|
| baseline-heavy | **40** | 10 × 16KB / 1ms | **~6+ GB/s** client-side | trigger network > 20 KB/s immediately |
| scale-out-2 | **80** | same | higher | scale to 3 nodes |
| scale-out-3 | **120** | same | higher | scale to 4 nodes |
| scale-in | **10** | same | low | scale back down |

Default publish settings: **interval=0.001s**, **payload=16384B**, **10 messages/burst**

Tune intensity if scaling is slow:

```powershell
$env:PUBLISH_INTERVAL = "0.02"   # faster publishes = more CPU
$env:PAYLOAD_SIZE = "1024"        # larger messages = more load
.\scripts\run_after_apply.ps1
```

Watch scaling in AWS Console -> EC2 -> Auto Scaling Groups, or CloudWatch alarm `emqx-prod-replicant-high-cpu`.

## 10) Monitoring

CloudWatch dashboard includes:
- ASG CPU
- NLB traffic metrics
- ASG in-service and desired capacity
- Memory metric via CWAgent

Alarms included:
- High CPU
- NLB unhealthy hosts
- ASG in-service too low

## 11) Frontend Demo Dashboard

Path: `frontend/nextjs-dashboard`

Run:

```bash
cd frontend/nextjs-dashboard
npm install
npm run dev
```

This dashboard is a presentation UI with mock API data for interview storytelling.

## 12) Terraform Best Practices Applied

- Module-per-domain architecture
- Inputs/outputs with no hardcoded sensitive values
- Shared tags and naming conventions
- Dedicated user-data templates
- Least-privilege IAM policy attachments
- Reusable networking and security layers

## 13) Estimated Cost (Demo)

Approximate (short-lived demo, ap-south-1):
- 3 x `t3.medium` cores
- 1-4 x `t3.medium` replicants (typically 1 in idle)
- NAT gateway + data processing
- NLB hourly + LCUs
- CloudWatch metrics/logs

Expected range for a brief interview run: low-to-moderate. Keep environment up only during testing to control cost.

## 14) SSH and Key Pair

- Terraform creates one shared key pair for all nodes.
- Generated private key path is exported as Terraform output.
- SSH access is controlled via `ssh_allowed_cidr`.
- SSM Session Manager is also enabled for SSH-less operations.
