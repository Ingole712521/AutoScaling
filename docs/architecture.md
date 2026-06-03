# EMQX on AWS — Architecture

## Root stack (primary)

Single core EC2 + ASG replicants behind an internet-facing NLB on **MQTT :1883**.

```mermaid
flowchart LR
  clients["MQTT clients"] --> nlb["NLB :1883"]
  nlb --> asg["Replicant ASG 1-4"]
  asg --> rep["Replicant nodes"]
  rep --> core["Core EC2 + EIP"]
  core --> ssm["SSM discovery params"]
  cw["CloudWatch alarms"] --- asg
  cw --- nlb
```

- Core is **not** in the NLB target group (dashboard on `:18083`).
- EMQX 5.8 OSS: all nodes are peer cluster members (no Enterprise `node.role`).
- Replicants join using SSM-published cluster seeds from the core.

## Modular stack (`terraform/`)

Optional layout: **3 core** nodes in private subnets, Route53 zone `emqx.internal`, replicants in private subnets. Same NLB + autoscaling pattern; apply from `terraform/` directory.

```mermaid
flowchart LR
  clients["MQTT clients"] --> nlb["NLB :1883"]
  nlb --> asg["Replicant ASG"]
  asg --> cores["Core x3 via Route53"]
```
