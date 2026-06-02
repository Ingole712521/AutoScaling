# EMQX on AWS - Architecture

## Mermaid Diagram

```mermaid
flowchart LR
  clients["MQTT Clients"] --> nlb["NLB :1883/:8883"]
  nlb --> asg["Replicant ASG (1-4)"]
  asg --> r1["Replicant Node(s)"]
  r1 --> c1["Core-1"]
  r1 --> c2["Core-2"]
  r1 --> c3["Core-3"]

  subgraph PrivateDNS["Route53 Private Zone: emqx.internal"]
    d1["core1.emqx.internal"]
    d2["core2.emqx.internal"]
    d3["core3.emqx.internal"]
  end

  c1 --- d1
  c2 --- d2
  c3 --- d3

  cw["CloudWatch Dashboard + Alarms"] --- asg
  cw --- nlb
  ssm["SSM Session Manager"] --- c1
  ssm --- asg
```

## Design Notes

- Core nodes are fixed and never auto-scaled.
- Replicant nodes are auto-scaled for client-facing MQTT load.
- NLB only forwards traffic to replicants.
- Route53 private DNS provides stable cluster seed discovery.
- SSM is enabled for SSH-less operations while SSH is also available for interview troubleshooting.
