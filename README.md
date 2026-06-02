# EMQX AWS Cluster (25k -> 100k users)

Production-ready baseline to deploy an EMQX cluster on AWS with:

- Multi-AZ network and private ECS services
- Network Load Balancer for MQTT/TCP traffic
- EMQX core + replicant services
- Autoscaling for replicants
- CloudWatch logging
- Optional k6 load test runner
- Clean Terraform structure split by responsibility
- ECS on EC2 capacity providers for explicit instance control

## Architecture

- EMQX core tasks (default `3`, configurable per phase)
- `N` EMQX replicant tasks behind autoscaling
- NLB listeners for MQTT and MQTT over TLS
- ECS on EC2 using Auto Scaling Group and capacity provider
- Core-first startup order so replicants join a healthy cluster
- Autoscaling-safe ECS config (`desired_count` drift ignored in Terraform)

## Prerequisites

- AWS account and credentials configured
- Terraform `>= 1.5`
- AWS CLI `>= 2.x`
- (Optional) k6 for external load generation

## Quick Start (Single Go)

1. Copy and edit variables:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Make sure to change at least:
- `emqx_dashboard_password`
- `emqx_node_cookie`

2. Initialize and deploy:

```bash
terraform init
terraform apply -auto-approve
```

3. Get MQTT endpoint:

```bash
terraform output mqtt_endpoint
```

4. Point devices/clients to the NLB DNS on port `1883` (or `8883` for TLS).

## Phased Rollout (Recommended)

This project uses **ECS on EC2**, so you can control instance type and count.
Use phased capacity files:

```bash
terraform apply -var-file="environments/phase1.tfvars" -auto-approve
```

After Phase 1 tests pass, scale up:

```bash
terraform apply -var-file="environments/phase2.tfvars" -auto-approve
```

Phase 1 is already pinned to `t2.small` with `1` instance, and Phase 2 scales to `2` instances.
These phases are for bootstrap validation only. For `25k-100k` clients, move to larger instance families and restore multi-core-node sizing.

## Scale Strategy

- Core service remains fixed at `3`.
- Replicant service scales between `2` and `20` tasks (configurable).
- Target tracking policy:
  - CPU target default: `60%`
  - Memory target default: `70%`

Tune these based on your workload characteristics.

## Capacity Notes

This template is built to scale toward `100,000` concurrent clients, but **exact capacity depends on**:

- message size/rate and QoS level
- retained/session behavior
- authentication backend latency
- TLS usage and cert overhead

You must run staged load tests (`25k`, `50k`, `75k`, `100k`) and adjust:

- task CPU/memory
- min/max replicant count
- protocol/auth settings

## Files

- `data.tf` - AWS data sources
- `locals.tf` - naming, tags, and shared EMQX env
- `network.tf` - VPC, subnets, routes, NAT
- `security.tf` - security groups for NLB and EMQX
- `loadbalancer.tf` - NLB, target groups, listeners
- `ecs.tf` - ECS cluster, CloudMap, task definitions, services
- `autoscaling.tf` - replicant service autoscaling policies
- `variables.tf` - input variables
- `outputs.tf` - useful outputs
- `terraform.tfvars.example` - editable defaults
- `scripts/run_load_test.sh` - k6 sample runner
- `loadtest/mqtt-k6.js` - k6 scenario template

## Destroy

```bash
terraform destroy -auto-approve
```

## Hardening Checklist (Recommended)

- Replace example EMQX dashboard credentials
- Use ACM + TLS termination or passthrough cert strategy
- Add AWS WAF/security controls around management endpoints
- Integrate external auth/ACL store (Redis/Postgres/HTTP auth)
- Configure alarms (connection drops, CPU saturation, memory pressure)
# EMQX_autoScaling
