---
title: "Network protection and inspection"
description: "Design WAF, Shield, Firewall Manager and Network Firewall controls with logging, symmetric paths and staged rollout."
tags:
  - cloud/aws/networking/security
date: 2026-10-12
---

# Network protection and inspection

Start with [[AWS/networking/networking-security/README|the network security overview]] and [[AWS/networking/load-balancing/README|load balancers]]. Application filtering, DDoS protection, centralized policy and routed inspection are different layers.

## Control boundaries

WAF rules evaluate according to configured order/actions. Managed/custom rules, rate-based controls and CAPTCHA/challenge behavior require scope and test traffic. Supported associations extend beyond ALB/CloudFront; inspect the resource/Region contract.

Shield Standard and Advanced have different features, enrollment, cost and support prerequisites. Do not assume protection for every resource or reimbursement for every event. Firewall Manager applies supported organization policy types with prerequisite service/configuration roles; it does not replace workload-owner review.

Network Firewall evaluates stateless rules/actions first and forwards selected traffic to stateful inspection. Route traffic to endpoints deliberately and preserve symmetric forward/return paths. An inspection appliance outside the path protects nothing.

## Staged WAF exercise

Prerequisites: a sandbox supported web resource, scoped WAF permissions and a spending limit.

1. Create a dedicated web ACL and associate it only with the sandbox resource.
2. Add a bounded test rule in Count mode. Send one matching and one non-matching request.
3. Inspect sampled requests/metrics and approved logs; redact sensitive headers/fields.
4. Switch only the test rule to Block and repeat; expect the matching request denied and the other accepted.
5. Restore Count or remove the rule if legitimate traffic is affected.
6. Disassociate/delete the dedicated ACL and log destination after acceptance.

Bot Control and CAPTCHA/challenge can add feature/request charges. A rate-based rule is not a perfectly hard instantaneous request cap.

## Inspection failure drill

For an existing sandbox routed inspection setup, trace source subnet → endpoint → destination and the return route. Change one sandbox route to demonstrate bypass or asymmetric failure, then restore it. Use reachability/configuration evidence and flow/firewall logs; do not claim Flow Logs contain full payloads.

For organization rollout, stage one account/OU, inspect compliance and exceptions, then expand with an explicit rollback. Never apply a new blocking policy across all production accounts as the first test.

## References

- [WAF rule processing](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-processing.html).
- [Firewall Manager prerequisites](https://docs.aws.amazon.com/waf/latest/developerguide/fms-prereq.html).
- [Shield](https://docs.aws.amazon.com/waf/latest/developerguide/shield-chapter.html).
- [Network Firewall engines](https://docs.aws.amazon.com/network-firewall/latest/developerguide/firewall-rules-engines.html).
- [WAF pricing](https://aws.amazon.com/waf/pricing/).
