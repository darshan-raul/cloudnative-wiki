---
title: Network Cost Optimization
description: Billing models, trade-offs, safe workflows and scoped examples for network cost optimization.
tags:
  - aws/cost-management
date: 2026-10-12
---

# Network Cost Optimization

Price exercises use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, not current tariffs, unless explicitly identified as a dated published fee.

Model network cost per traffic path: source, destination, Region/AZ, direction, GB, intermediaries and applicable service exemptions. There is no universal per-GB rate for all AWS traffic.

## Path choices

| Component                     | Cost model and caution                                                   |
| ----------------------------- | ------------------------------------------------------------------------ |
| NAT Gateway                   | Gateway hours plus processed GB; transfer/public IPv4 can add charges    |
| S3/DynamoDB gateway endpoints | No endpoint hourly or processing fee; underlying service charges remain  |
| Interface endpoints           | Endpoint hours per AZ and processed data under PrivateLink pricing       |
| VPC peering                   | No peering connection fee; cross-AZ/inter-Region transfer may be charged |
| Transit Gateway               | Attachment hours and applicable processed GB                             |
| Direct Connect                | Port-hours, transfer and possible provider/cross-connect charges         |
| ALB                           | Load-balancer hours plus LCUs based on the highest applicable dimension  |
| NLB                           | Load-balancer hours plus NLCUs, with protocol-specific dimensions        |

ALB LCU dimensions include connections, active connections, processed bytes and rule evaluations; they are not simply requests or a flat 100-rules entitlement. NLB uses NLCUs, not invented NCUs, and is not always cheaper.

Load balancers cannot be stopped like EC2. Instance Scheduler targets supported EC2/RDS resources, not an ALB stop API. Removing a dev load balancer requires dependency review and reprovisioning plans.

## Worked NAT example

Assume a NAT gateway rate of \$0.045/hour and \$0.045/GB, 720 hours and 500 GB processed:

```text
gateway = 720 × $0.045 = $32.40
processing = 500 × $0.045 = $22.50
subtotal = $54.90
```

This excludes public IPv4 and transfer. Moving eligible S3/DynamoDB traffic to gateway endpoints removes those NAT processing charges, not substitutes an invented \$0.01/GB gateway-endpoint charge. Remaining internet traffic still needs its egress path.

## Reliability and delivery

Keep redundant egress/connectivity according to SLOs. Same-AZ traffic affinity can reduce some charges, but consolidating all production components into one AZ is not a safe universal optimization. ALB cross-zone and data-transfer charging have service-specific exceptions; do not price every hop identically.

S3-to-CloudFront origin transfer is waived under the applicable AWS pricing rules; cache misses can still incur origin request/retrieval and CloudFront charges. Compare the actual CloudFront pricing plan and geography. Direct Connect is billed in port-hours, not port-minutes; there is no universal 10-TB economic break-even.

## Trace the billable path

| Traffic                          | Questions before pricing                                        |
| -------------------------------- | --------------------------------------------------------------- |
| EC2 → same-AZ private service    | Which service and address path? Are exceptions applicable?      |
| EC2 → cross-AZ peered VPC        | Which endpoints/directions incur regional transfer?             |
| VPC Lambda → private RDS         | Local routing or cross-AZ path? NAT is not inherently involved  |
| Private worker → public internet | NAT hours/processing, transfer and public IPv4?                 |
| On-premises → AWS                | DX port/provider plus transfer, or VPN connection/transfer?     |
| Viewer → CloudFront → S3         | Cache hit, request/retrieval and current delivery-plan charges? |

Avoid a universal “same Region peering is free” rule. Trace central egress: a NAT in another AZ can add transfer and a failure dependency. Choose resilient routing first; compare cost of distributed versus centralized egress including TGW/endpoint paths.

## Endpoint break-even worksheet

Assume an interface endpoint in two AZs at a hypothetical \$0.01/AZ-hour and \$0.01/GB, versus a dedicated NAT at \$0.045/hour plus \$0.045/GB. For this us-east-1 study exercise on 2026-10-12, use 720 hours and 1,000 GB:

```text
interface endpoint = 2 × 720 × $0.01 + 1,000 × $0.01 = $24.40
dedicated NAT      = 720 × $0.045 + 1,000 × $0.045 = $77.40
```

If NAT must remain for other internet traffic, its fixed hours are not avoidable; the incremental comparison changes. These assume supported service/path and exclude transfer/IPv4. Gateway S3/DynamoDB endpoints have no endpoint fee and should not be priced using the interface formula.

## Load-balancer and delivery cost

For an ALB calculation, compute usage for new connections, active connections, processed bytes and rule evaluations under the actual configuration/certificate/target rules. Billing uses the highest applicable LCU dimension, not their sum. NLB dimensions vary by protocol and use NLCUs; CLB follows a distinct legacy model.

Do not disable cross-zone or reduce AZs solely from a guessed transfer rate. Some ELB transfer paths have exemptions, and unhealthy-AZ capacity changes can break reliability. An idle load balancer can be removed only through a reviewed delete/recreate workflow; it cannot be “stopped.”

CloudFront cache hits reduce origin request/retrieval work. A miss does not universally incur S3 egress to CloudFront, but origin GET/class retrieval can remain. Compare the actual pricing plan and geography, cache key/TTL, invalidations and viewer transfer. For DX, add provider and cross-connect costs; no 10-TB threshold guarantees economic superiority.

## References

- [VPC and NAT pricing](https://aws.amazon.com/vpc/pricing/)
- [PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/)
- [ELB capacity-unit pricing](https://aws.amazon.com/elasticloadbalancing/pricing/)
- [Direct Connect pricing](https://aws.amazon.com/directconnect/pricing/)
- [CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/)

## Across the wiki

- [[GCP/networking/vpc/cloud-nat|GCP Cloud NAT Deep Dive & SNAT Port Allocation]] — NAT and egress (GCP)
- [[Architecture/solution-architecture-concepts/networking/nat|Nat]] — NAT and egress (Architecture)

- [VPC endpoint architecture](https://docs.aws.amazon.com/vpc/latest/privatelink/concepts.html).
- [Cross-AZ EC2 transfer](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-network-bandwidth.html).
