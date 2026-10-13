---
title: AWS Elastic Load Balancing
description: Choose ALB, NLB or GWLB by protocol and traffic path, then test target health, scoped access and reversible deployment.
tags:
  - cloud/aws/networking
date: 2026-10-12
---

# AWS Elastic Load Balancing

ELB provides ALB, NLB, GWLB and legacy CLB offerings. Start with [[AWS/networking/vpc/README|routing]] and [[AWS/networking/vpc/security-groups|SGs]]. Protocol, health checking and inspection requirements determine the choice.

## Product boundaries

| Type | Primary role                                                      | TLS and addressing                                             |
| ---- | ----------------------------------------------------------------- | -------------------------------------------------------------- |
| ALB  | HTTP/HTTPS request routing, supported gRPC/WebSocket integrations | TLS termination; no fixed-IP contract                          |
| NLB  | Supported transport-level TCP/UDP/TLS routing                     | TCP pass-through or TLS listener termination; per-AZ addresses |
| GWLB | Distribute traffic to supported virtual appliances using GENEVE   | Inspection topology, not an HTTP application router            |
| CLB  | Legacy load balancing                                             | No HTTP/2 or static-IP promise; plan a supported migration     |

NLB can allocate supported addresses or use configured EIPs where applicable; an EIP is not required for every NLB deployment. Select public/internal scheme and enabled AZs explicitly.

## Health and security

ALB listeners use HTTP/HTTPS, not generic TCP listeners. ALB health checks use HTTP/HTTPS GET with configured path/matcher; /health is an example, not mandatory. Use NLB when a supported TCP health check meets the requirement.

Allow only intended clients on the listener port. Public 0.0.0.0/0 is optional, not a requirement for internal or restricted-client ALBs. Permit LB-to-target application/health traffic with supported SG references, and check NACL forward/return paths.

A target's health does not prove every application dependency works. Configure deregistration delay, application draining and deployment health checks according to actual request/connection lifetimes rather than a fixed “stateless means sixty seconds” rule.

## Two-target sandbox exercise

Prerequisites: two sandbox subnets/AZs, two disposable HTTP targets with a known marker/health endpoint, scoped ELB/EC2 permissions and a budget.

1. Create a dedicated ALB with the intended scheme and client SG.
2. Create a compatible target group/port/protocol and register both actual targets.
3. Create an HTTP/HTTPS listener with a default forward action; if HTTPS, use a compatible regional certificate.
4. Inspect target health, invoke the returned DNS name and verify both target markers over repeated requests.
5. Break only one sandbox health endpoint. Observe the unhealthy reason and traffic distribution; restore it.
6. Deny the test client on the LB SG, start a new connection and confirm failure; restore the intended rule.
7. Deregister/drain targets, delete listener/LB and the dedicated target group, then remove disposable targets/groups/logs after dependencies clear.

Expected evidence: listener/action configuration, target-health reason, allowed/denied client test and recovery. A created LB ARN is not a deployment checkpoint.

For GWLB, follow [[AWS/networking/protection-and-inspection|the inspection path drill]] and a supported appliance's setup; routing both directions through the endpoint is part of the design.

## Cost and capacity

### Cross-zone routing and uneven capacity

ALB has cross-zone routing enabled at the load-balancer level; supported target groups can override it to off. NLB defaults to off at the load-balancer level; target groups can inherit or override the setting. Inspect both levels rather than guessing from the product name. [ALB configuration](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-target-group-attributes.html), [NLB configuration](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/edit-target-group-attributes.html).

```text
Cross-zone off: AZ-A node → AZ-A targets; AZ-B node → AZ-B targets
Cross-zone on:  either node → eligible targets across enabled AZs
```

If half the incoming traffic reaches each AZ but A has two targets and B has eight, off leaves each A target handling roughly four times the load of each B target, under an equal-target-work assumption. On can reduce this skew but cannot create missing capacity or guarantee equal work for unequal requests. Retain enough local capacity when disabling it, and measure transfer/capacity charges for the selected product rather than copying a universal surcharge.

### Target affinity versus deployment weights

ALB duration-based stickiness uses load-balancer cookies; application-based stickiness uses an application cookie plus load-balancer handling. Affinity is unavailable with cross-zone disabled. Weighted forwarding has a separate target-group-stickiness setting: choosing a group is different from choosing a target inside it. [Forward-action contract](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/rule-action-types.html).

For the two-target ALB lab, retain the original target-group attributes, then enable duration-based affinity for 60 seconds:

```bash
aws elbv2 describe-target-group-attributes --target-group-arn "$ELB_LAB_TG_ARN"
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$ELB_LAB_TG_ARN" \
  --attributes Key=stickiness.enabled,Value=true \
    Key=stickiness.type,Value=lb_cookie \
    Key=stickiness.lb_cookie.duration_seconds,Value=60
curl -fsS -c elb-lab-cookies.txt "http://$ELB_LAB_DNS/"
curl -fsS -b elb-lab-cookies.txt "http://$ELB_LAB_DNS/"
```

Set these variables to the dedicated group's ARN and reachable HTTP listener DNS name. The second request should retain the marker while its selected target stays eligible. Repeat without cookies; then fail that target and verify rerouting. Affinity does not preserve in-memory session data when the target disappears: use a durable/shared session store where required. Restore the recorded attributes and remove the local cookie file. Do not enable this test on a shared target group.

ALB capacity units use the maximum applicable dimension across connections, processed bytes and rule evaluations. Monthly request count alone cannot determine LCUs. NLB uses its protocol-specific connection/byte dimensions; 10 Gbps is not universally ten NLCUs.

Price LB-hours, measured capacity units, public addresses, logs and applicable transfer. Do not compare two products using guessed capacity units or different workloads. Check current account/Region quotas and required address capacity before launch.

## Request path and ALB versus NLB choices

```text
DNS → load balancer listener → ordered rule → target group → healthy target
               │                              │
        client SG / certificate       target SG / health path
```

| Need                               | Start with | Verify                                              |
| ---------------------------------- | ---------- | --------------------------------------------------- |
| Route by HTTP host/path/header     | ALB        | Rule priority, target group and health matcher      |
| Pass supported TCP/UDP traffic     | NLB        | Listener/target protocol and client IP requirements |
| Inspect traffic through appliances | GWLB       | Symmetric routes and appliance health               |

For an ALB, a listener has a default action and can evaluate additional rules in priority order. A healthy target must be registered, attached through a rule, in an enabled AZ and able to answer its health request. `unused` can mean the group is not referenced or the target's AZ is disabled; `unhealthy` carries reason codes such as timeout or response-code mismatch. If every registered target is unhealthy, ALB can fail open to those targets, so an all-red health dashboard is a serious incident rather than a guarantee of zero traffic. See the [target-health contract](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html).

During deployment, set draining long enough for actual requests/streams and check application readiness separately from process liveness. For an internal service, keep the scheme and SG scoped to intended callers; DNS visibility by itself does not grant a network path. For a cost worksheet, measure the actual hourly LB charge and each applicable capacity dimension before comparing ALB and NLB.

## References

- [ELB protocols and behavior](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/how-elastic-load-balancing-works.html).
- [ALB health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html).
- [ALB security groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-update-security-groups.html).
- [NLB TLS listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/create-tls-listener.html).
- [Gateway Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/gateway/introduction.html).
- [Pricing and capacity-unit dimensions](https://aws.amazon.com/elasticloadbalancing/pricing/).

## Across the wiki

- [[Azure/compute/aks/ingress-appgw-gateway|AKS Ingress, Application Gateway for Containers, and Gateway API Architecture]] — ingress and load balancing (Azure)
- [[GCP/compute/gke/gateway-api|GKE Gateway API Architecture, HTTPRoute, and Cloud Armor Integration]] — ingress and load balancing (GCP)
- [[Kubernetes/concepts/L04-services-networking/09-gateway-api|Gateway API]] — ingress and load balancing (Kubernetes)
- [[Architecture/solution-architecture-concepts/reliability/load-balancing|Load Balancing]] — ingress and load balancing (Architecture)
