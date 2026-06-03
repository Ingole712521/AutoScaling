# EMQX 5.x MQTT Cluster on AWS — Complete Documentation

> **Project:** Interview-grade EMQX demo on AWS (Terraform)  
> **Region:** ap-south-1  
> **Last updated:** June 2026  
> **Stack:** EMQX 5.8.9 OSS, Ubuntu 22.04, native DEB install (no Docker)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture](#architecture)
3. [AWS Services Used](#aws-services-used)
4. [Project Structure](#project-structure)
5. [Deployment Guide](#deployment-guide)
6. [EMQX Cluster Design](#emqx-cluster-design)
7. [Auto Scaling](#auto-scaling)
8. [Load Balancer](#load-balancer)
9. [Load Test Guide](#load-test-guide)
10. [Monitoring & Verification](#monitoring--verification)
11. [Troubleshooting](#troubleshooting)
12. [Interview Talking Points](#interview-talking-points)
13. [Cost Estimate](#cost-estimate)
14. [Lessons Learned](#lessons-learned)

---

## Executive Summary

This project deploys a **production-style EMQX 5.x MQTT broker cluster** on AWS using **Terraform only**. It demonstrates:

- **1 fixed core node** for cluster coordination and dashboard access
- **1–4 replicant nodes** in an Auto Scaling Group for client MQTT traffic
- **Network Load Balancer (NLB)** on port **1883** for MQTT
- **Step-based autoscaling** (+1 / −1) driven by network and CPU alarms
- **Automated bootstrap** via user-data script (no manual SSH fixes)
- **Staged MQTT load test** to trigger scale-out and scale-in during demos

---

## Architecture

### High-Level Diagram

```
                    Internet / Demo clients
                              |
                              v
              +-------------------------------+
              |  NLB (MQTT 1883, TCP)         |
              +-------------------------------+
                              |
              +---------------+---------------+
              |   Replicant ASG (1-4 nodes)   |
              |   t3.small, public subnets    |
              +---------------+---------------+
                              |
                    cluster join (Erlang)
                              |
              +-------------------------------+
              |  Core node (fixed, 1x EC2)    |
              |  Dashboard :18083, EIP        |
              +-------------------------------+
                              |
              SSM: core-private-ip, cluster-seeds
```

### Network Layout

| Component | CIDR / Detail |
|-----------|----------------|
| VPC | 10.0.0.0/16 |
| Public subnets | 10.0.1.0/24, 10.0.2.0/24 |
| Region | ap-south-1 |

### Node Roles

| Role | Count | Purpose |
|------|-------|---------|
| **Core** | 1 (fixed EC2) | Cluster metadata, coordination, **dashboard on :18083** |
| **Replicant** | 1–4 (ASG) | Client MQTT traffic via NLB; scales with load |

**Dashboard node count:** 1 core + N replicants = **2 to 5 nodes** in EMQX UI.

---

## AWS Services Used

- **EC2** — core + replicant instances
- **Auto Scaling Group** — replicant capacity
- **Network Load Balancer** — MQTT TCP :1883
- **VPC / Subnets / IGW** — networking
- **Elastic IP** — stable core public IP for dashboard
- **IAM** — instance profile (SSM, minimal policies)
- **SSM Parameter Store** — `core-private-ip`, `cluster-seeds` for dynamic cluster join
- **Systems Manager** — Session Manager (SSH-less ops)
- **CloudWatch** — CPU/network metrics, scaling alarms

---

## Project Structure

```
emqx/
├── autoscaling.tf          # Step scaling policies + CloudWatch alarms
├── emqx_core.tf            # Core EC2 + EIP
├── emqx_replicants.tf      # NLB, target group, launch template, ASG
├── vpc.tf, security.tf, iam.tf, ssm.tf
├── variables.tf, outputs.tf
├── userdata/
│   └── emqx-bootstrap.sh   # Single bootstrap for core + replicant
├── loadtest/
│   └── staged_load.py      # Staged MQTT load test
├── scripts/
│   ├── deploy_and_load_test.ps1
│   ├── run_staged_load_test.ps1
│   ├── verify_deployment.ps1
│   ├── watch_bootstrap.ps1
│   └── run_after_apply.ps1
└── terraform.tfvars.example
```

---

## Deployment Guide

### Prerequisites

- AWS CLI configured
- Terraform >= 1.x
- Python 3 + `paho-mqtt` (for load test)
- PowerShell (Windows) or Bash (Linux/macOS)

### Step 1 — Configure secrets

```powershell
cd "d:\New folder\emqx"
copy terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

| Variable | Required |
|----------|----------|
| `emqx_node_cookie` | Yes — Erlang cluster cookie |
| `emqx_dashboard_password` | Yes |
| `dashboard_allowed_cidr` | Your IP/32 or `0.0.0.0/0` for demo |
| `ssh_allowed_cidr` | Optional |

### Step 2 — Deploy

**One command (recommended):**

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy_and_load_test.ps1
```

**Manual:**

```powershell
terraform init
terraform apply
powershell -ExecutionPolicy Bypass -File .\scripts\verify_deployment.ps1
```

### Step 3 — Wait for bootstrap (~10 minutes)

After apply, EC2 shows **Running** quickly, but EMQX is not ready until:

- `emqx-bootstrap.sh` finishes (apt, EMQX install, cluster join)
- NLB target health = **healthy**
- Ports **1883** (MQTT) and **18083** (dashboard) respond

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\watch_bootstrap.ps1
```

### Terraform Outputs

| Output | Description |
|--------|-------------|
| `emqx_dashboard_url` | `http://<core-eip>:18083` |
| `mqtt_nlb_dns_name` | NLB DNS for MQTT clients |
| `mqtt_broker_url` | `tcp://<nlb-dns>:1883` |
| `replicant_asg_name` | `emqx-prod-replicants-asg` |

---

## EMQX Cluster Design

### Bootstrap (`userdata/emqx-bootstrap.sh`)

- Installs EMQX 5.8.x from official DEB repo
- Config via **`/etc/emqx/terraform.env`** + systemd drop-in (not invalid `conf.d` paths)
- **Core:** writes private IP to SSM; seeds cluster
- **Replicant:** reads SSM at boot for current core IP (works on scale-out)
- Listeners: **1883** (MQTT), **18083** (dashboard on core)

### Core vs Replicant

| | Core | Replicant |
|---|------|-----------|
| Provisioning | Fixed EC2 | ASG |
| NLB target | No | Yes |
| Dashboard | Yes (EIP) | No (via cluster UI only) |
| Scales | No | Yes (1–4) |

### SSM Parameters

- `/${project_name}/core-private-ip`
- `/${project_name}/cluster-seeds`

Replicants use these at boot so new ASG instances join the correct cluster without stale baked-in IPs.

---

## Auto Scaling

### Policies (current — step scaling)

| Policy | Trigger | Action |
|--------|---------|--------|
| `replicants-scale-out-network` | NetworkIn > 20 KB/s for **2 min** | **+1** |
| `replicants-scale-out-cpu` | CPU > **1%** for 1 min | **+1** |
| `replicants-scale-in-cpu` | CPU < **3%** for 2 min | **−1** |

| ASG setting | Value |
|-------------|-------|
| Min | 1 |
| Max | 4 |
| Desired (start) | 1 |
| Cooldown | 60 sec |
| Health check grace | 600 sec |

### Why we changed from target tracking

**Problem:** On `terraform apply`, bootstrap traffic (`apt`, EMQX download) spiked network metrics. **Target tracking** jumped desired capacity **1 → 4 instantly** with no MQTT load.

**Fix:** **Step scaling (+1)** + **2 evaluation periods** for network alarm. Scale-out now grows **1 → 2 → 3 → 4** during the load test only.

### Scale-in behavior

- Idle EMQX nodes sit at **~0.6–2% CPU** (not below 0.5%)
- Scale-in threshold set to **CPU < 3%** for 2 minutes
- Removes **one instance at a time**; expect **~10–15 min** after load stops to return to 1 replicant

### What to watch in AWS Console

**EC2 → Auto Scaling Groups → Activity history:**

- Scale out: `Launching a new EC2 instance` (+1 each time)
- Scale in: `Terminating EC2 instance` (−1 each time)

---

## Load Balancer

- **Type:** Network Load Balancer (Layer 4 TCP)
- **Port:** 1883
- **Targets:** Replicant instances only (core not in target group)
- **Health check:** TCP on 1883
- **Cross-zone:** Enabled

---

## Load Test Guide

### Run load test

**After NLB target is healthy** (~10 min post-apply):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_staged_load_test.ps1 -FromTerraform
```

Or:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_staged_load_test.ps1 -MqttHost "YOUR-NLB-DNS.elb.ap-south-1.amazonaws.com"
```

### Default stages (~19 minutes)

| Stage | Clients | Duration | Goal |
|-------|---------|----------|------|
| baseline-heavy | 40 | 180s | First +1 scale-out |
| scale-out-2 | 80 | 300s | Second +1 |
| scale-out-3 | 120 | 300s | Third +1 |
| scale-in | 10 | 360s | Reduce load for scale-in |

**Publish settings:** interval=0.001s, payload=16KB, burst=10 messages

### Expected demo timeline

```
00:00  terraform apply → 1 replicant
00:10  bootstrap done, NLB healthy
00:11  start load test
00:14  ASG 1 → 2 (stage 1)
00:19  ASG 2 → 3 (stage 2)
00:24  ASG 3 → 4 (stage 3)
00:30  stage 4 (lower clients)
00:45+ scale-in 4 → 3 → 2 → 1 (after load stops)
```

### Verify MQTT before load test

```powershell
python -c "import paho.mqtt.client as mqtt; c=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2); c.connect('YOUR-NLB',1883,30); print('OK'); c.disconnect()"
```

If this times out, **wait for bootstrap** — do not run load test yet.

---

## Monitoring & Verification

### EMQX Dashboard

- URL: `http://<core-public-ip>:18083`
- Login: `admin` + password from `terraform.tfvars`
- Watch: **Nodes**, **Messages In**, **Connections**

### Scripts

| Script | Purpose |
|--------|---------|
| `verify_deployment.ps1` | Port checks, summary |
| `watch_bootstrap.ps1` | SSM bootstrap logs |
| `run_staged_load_test.ps1` | Autoscaling demo load |

### AWS CLI checks

```powershell
# ASG capacity
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names emqx-prod-replicants-asg --region ap-south-1 --query "AutoScalingGroups[0].DesiredCapacity"

# NLB target health
aws elbv2 describe-target-health --target-group-arn <arn> --region ap-south-1
```

---

## Troubleshooting

### Issue: 4 instances launch right after apply (no load)

**Cause:** Bootstrap network traffic triggered old target-tracking policy.  
**Fix:** Use current `autoscaling.tf` (step scaling). Run `terraform apply`.

### Issue: Scale-in never happens

**Cause:** CPU threshold too low (0.5%); idle EMQX ~1–2% CPU.  
**Fix:** Scale-in at CPU < **3%** for 2 minutes (already in current config).

### Issue: Load test shows `errors=40`, `published=0`

**Cause:** NLB target still **initial** / EMQX not ready.  
**Fix:** Wait ~10 min; confirm target **healthy** before load test.

### Issue: ASG launch failed (vCPU limit)

**Cause:** Orphan instances from failed runs still running.  
**Fix:** Terminate extra EC2 instances; `terraform destroy` then `apply`.

### Issue: Dashboard/MQTT unreachable after apply

**Cause:** Past cloud-init / config path errors (fixed in bootstrap).  
**Fix:** Check `/var/log/emqx-bootstrap.log` via SSM; re-apply with fixed `emqx-bootstrap.sh`.

---

## Interview Talking Points

1. **Architecture:** Core/replicant split — stable control plane, elastic data plane for MQTT clients.

2. **Discovery:** SSM parameters let new replicants discover core IP at boot without hardcoding.

3. **Scaling:** Step scaling (+1) avoids bootstrap false positives; network + CPU alarms for demo sensitivity.

4. **Load balancing:** NLB TCP passthrough to replicants only; core isolated for ops/dashboard.

5. **IaC:** Single Terraform root module; one bootstrap script; repeatable deploy + load test scripts.

6. **Trade-off:** Demo thresholds (20 KB/s, 1% CPU) are intentionally low for visibility, not production values.

---

## Cost Estimate (Demo, ap-south-1)

| Resource | Approx. |
|----------|---------|
| 1× core t3.small | ~$15/mo if left on |
| 1–4× replicant t3.small | variable |
| NLB | hourly + LCU |
| Data transfer | load-test dependent |

**Tip:** `terraform destroy` when not demoing.

---

## Lessons Learned

| Topic | Lesson |
|-------|--------|
| Target tracking | Can scale 1→max in one alarm; bad for bootstrap spikes |
| Step scaling | +1 per alarm = predictable interview demo |
| CPU scale-in | Must exceed idle EMQX baseline (~1–2%) |
| Bootstrap | EC2 "Running" ≠ EMQX ready; wait for NLB healthy |
| EMQX 5.8 config | Use env overrides + systemd drop-in, not arbitrary conf.d paths |
| User-data | `templatefile()` for bash; avoid indented heredoc breaking `#!/bin/bash` |

---

## Quick Reference Commands

```powershell
# Deploy
terraform apply

# Verify
powershell -ExecutionPolicy Bypass -File .\scripts\verify_deployment.ps1

# Load test
powershell -ExecutionPolicy Bypass -File .\scripts\run_staged_load_test.ps1 -FromTerraform

# Destroy
terraform destroy
```

---

## Appendix — Autoscaling Variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `scale_out_network_target_bytes` | 20000 | Scale out +1 when exceeded (bytes/sec) |
| `scale_out_network_evaluation_periods` | 2 | Minutes of high network required |
| `scale_out_cpu_threshold` | 1 | Backup scale-out % |
| `scale_in_cpu_threshold` | 3 | Scale-in % |
| `autoscaling_cooldown_sec` | 60 | Between scale actions |
| `replicant_min_size` | 1 | Minimum replicants |
| `replicant_max_size` | 4 | Maximum replicants |

---

*End of document*
