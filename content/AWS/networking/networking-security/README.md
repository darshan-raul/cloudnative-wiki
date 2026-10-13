---
title: "AWS network security"
description: "Separate ENI/subnet filtering, application protection, DDoS coverage, routed inspection and traffic-metadata analysis."
tags:
  - cloud/aws/networking/security
date: 2026-10-12
---

# AWS network security

Network security is a set of scoped controls, not a single firewall. Start with [[AWS/networking/vpc/README|routing]] and [[AWS/security/iam/policy-evaluation|authorization]].

## Control map

| Control                                     | Scope                                     | Important limitation                          |
| ------------------------------------------- | ----------------------------------------- | --------------------------------------------- |
| [[AWS/networking/vpc/security-groups\|SGs]] | ENI stateful allow                        | No explicit deny rules                        |
| [[AWS/networking/vpc/network-acls\|NACLs]]  | Subnet stateless allow/deny               | Return paths need explicit rules              |
| WAF                                         | Supported application associations        | Not every protocol/resource is covered        |
| Shield                                      | Supported DDoS protection plans/resources | Enrollment/support/product scope matters      |
| Network Firewall                            | Routed packet/stateful inspection         | Traffic must traverse endpoints symmetrically |
| Firewall Manager                            | Supported organization policies           | Prerequisites and rollout scope remain        |
| Flow Logs                                   | Traffic metadata                          | Exclusions; no full payload capture           |

Use [[AWS/networking/protection-and-inspection|the protection/inspection lesson]] for WAF Count→Block tests, organization rollout and firewall-route drills.

## Inspection pipeline

Network Firewall inspects stateless rules first. A matching or default action can drop, pass, or forward traffic to the stateful engine. Stateless rules are not a final stage after stateful inspection.

Define source→endpoint→destination and return routes per AZ. Appliance placement alone does not insert inspection. Preserve an approved bypass/rollback path and test asymmetric-routing failure only in a sandbox.

## Flow-log investigation exercise

Prerequisites: a sandbox client/server with approved access, a dedicated supported log destination/role and a log-retention budget.

1. Enable a scoped Flow Log and record aggregation/delivery settings.
2. Create one allowed and one denied **new** test flow.
3. Query ACCEPT/REJECT, interface, endpoints and timestamps.
4. Correlate REJECT with SG/NACL/effective routes; implicit SG denial can generate REJECT.
5. Explain documented exclusions and delayed/missing records before concluding no traffic occurred.
6. Remove the dedicated Flow Log and disposable log destination after preserving evidence.

NACLs do not create separate explicit-deny logs. Logs are metered by telemetry dimensions, not a direct percentage of network GB.

## Layered inspection example

```text
viewer → CloudFront/WAF → ALB → application SG → private service
                          │                 │
                          │          VPC Flow Logs metadata
                          └─ WAF sampled requests and logs

private egress → subnet route → Network Firewall endpoint → NAT/IGW
return traffic ─────────────── same inspection path ────────────→ source
```

WAF web ACLs attach to supported application resources and evaluate ordered rules or managed groups. Use Count first for a new match so you can inspect false positives before Block. Rate-based rules and managed groups have distinct tuning/charges. Shield Standard's included protection and Shield Advanced's subscribed coverage, response features and eligibility differ; neither means every HTTP misuse is automatically stopped. Security groups govern ENIs and cannot replace a WAF rule that looks at HTTP content.

| Observation                       | Likely source                              | Next question                                            |
| --------------------------------- | ------------------------------------------ | -------------------------------------------------------- |
| WAF Count or Block metric rises   | Matching request at the associated web ACL | Which rule matched and were legitimate clients affected? |
| ALB 5xx with healthy network path | Application/target or load balancer        | What do target health and backend logs show?             |
| Flow Log `REJECT`                 | SG/NACL/effective packet policy            | Which ENI and direction?                                 |
| Firewall drop/alert               | Routed inspection policy                   | Did both directions traverse the intended endpoint?      |

For a managed WAF rule group, enable the rule in Count in a lab, send normal and known-test requests, inspect sampled requests/logs, then change only the intended rule action after tuning exclusions. Log delivery needs explicit configuration and retention; a blocked request is not guaranteed to appear in an unrelated ALB application log. Rate-based protection can affect many legitimate users sharing one egress IP, so exercise a benign high-rate path before enabling a production block.

### Flow-log query and cost worksheet

With a dedicated CloudWatch Logs destination containing plain-text VPC Flow Log records, begin with a broad Insights query and inspect the actual field layout before adding a parser:

```text
fields @timestamp, @message
| filter @message like /REJECT/
| sort @timestamp desc
| limit 20
```

Correlate interface ID and source/destination with the effective SG/NACL and route path. The returned `REJECT` does not identify the exact denying rule on its own. For cost, list WAF web ACL/rule/request charges, optional managed-rule/bot features, Shield subscription if selected, firewall endpoint/processing charges, and log ingestion/retention separately. Apply current regional rates to measured units; network throughput is not the same quantity as stored log bytes.

Network Firewall applies stateless and stateful rules to routed traffic. Its endpoints must be placed in the selected AZ path; bypass routes or asymmetric return routing can make an apparently correct policy ineffective. Test both allow and deny from controlled sources and confirm the firewall's logging mode before using absence of a log as evidence.

For incident triage, correlate timestamps from WAF logs, ALB access/health logs, Flow Logs, firewall logs and application logs. Each records different data and has delivery/retention limits. Flow Logs contain flow metadata, not request bodies, and an `ACCEPT` record does not certify successful application authorization.

## References

- [Firewall engines](https://docs.aws.amazon.com/network-firewall/latest/developerguide/firewall-rules-engines.html).
- [Flow-log record examples](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-records-examples.html).
- [Flow-log limitations](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html).
- [WAF/Shield documentation](https://docs.aws.amazon.com/waf/latest/developerguide/what-is-aws-waf.html).
