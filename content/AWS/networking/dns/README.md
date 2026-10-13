---
title: "Amazon Route 53 and DNS"
description: "Separate public/private naming, alias behavior, routing policy and cached failover, with a controlled DNS test."
tags:
  - cloud/aws/networking/dns
date: 2026-10-12
---

# Amazon Route 53 and DNS

Route 53 provides hosted DNS and related routing/health capabilities. DNS selects names/answers; it is not an application proxy or an instantaneous failover controller.

## Name and routing boundaries

Public hosted zones require correct registrar/parent delegation. Private hosted zones require supported VPC associations and resolver paths; they are not automatically visible across every peering/hybrid connection.

Simple, weighted, latency, failover and other routing policies solve different requirements. Health-check configuration and EvaluateTargetHealth have target-specific behavior; a configured record alone does not prove the target is healthy.

Alias records inherit relevant target/aliased-record TTL behavior; they do not all use a fixed 300-second TTL. Cached answers, client connection reuse and health evaluation affect switching time. Domain registration and hosted-zone billing are separate.

## Controlled record exercise

Prerequisites: a sandbox hosted zone/domain you control, one disposable record, scoped DNS permissions and working authoritative delegation.

1. Add a low-TTL test record for a nonsensitive endpoint and record its value.
2. Query the authoritative server and a recursive resolver; compare answer/TTL.
3. Change the record to another sandbox endpoint, then observe cached versus authoritative answers.
4. If testing failover, induce a sandbox health failure and record detection plus resolver/client convergence.
5. Restore/delete only the test records. Do not delete shared zone delegation or production records.

Expected: a documented interval during which clients can still use the old answer. Explain why “DNS rollback is instant” is false.

## Hybrid DNS and security

Use [[AWS/networking/private-access-and-hybrid-dns|Resolver inbound/outbound rules]] for approved hybrid namespaces. Avoid loops and unintentionally shadowing public zones.

DNSSEC signing/validation have different zone/resolver roles; DNSSEC does not encrypt DNS traffic. Follow the owning setup, delegation and rollover procedures rather than enabling one switch and claiming complete protection.

## Pricing and capacity

Count billable queries by routing type, hosted zones, health-check options, resolver endpoints/queries and registration. Record count does not equal query volume.

At an illustrative \$0.40 per million standard queries, 100 million queries cost \$40 before allowances/other charges. Latency-routing queries have their own tariff. Do not multiply a health-check price by arbitrary checker locations or call the result a Region fee.

Check account/zone limits and current target TTL rules at the source; apply effective quotas rather than copied universal tables.

## Record and policy comparison

### Record types beyond addresses

Records describe data; routing policies choose which matching record answers. Do not treat weighted/failover as additional DNS record types.

| Type | Purpose                                     | Example / boundary                                                                                                   |
| ---- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| MX   | Mail routing with preference                | `10 mail.example.com.`; smaller preference is preferred                                                              |
| TXT  | Verification and application-defined text   | SPF and DKIM use TXT; do not create the obsolete SPF type for new mail configuration                                 |
| NS   | Authoritative delegation                    | Delegate `lab.example.com` at its parent to the child zone's returned name servers                                   |
| SOA  | Zone authority and timing metadata          | Route 53 supplies it with the zone; not an application endpoint record                                               |
| PTR  | Reverse lookup                              | An address's reverse namespace must be controlled/delegated; a forward-zone PTR does not create internet reverse DNS |
| SRV  | Service location, priority, weight and port | `_demo._tcp.lab.example.com. 10 5 8080 host.lab.example.com.`                                                        |
| CAA  | Which certificate authorities may issue     | `0 issue "amazon.com"`; coordinate with certificate issuance requirements                                            |

These complement A/AAAA, CNAME and supported alias targets below. For example, a child-zone NS delegation is different from adding a CNAME to the child name. TXT ownership verification does not authorize arbitrary certificate issuers. See [Route 53 record types](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/ResourceRecordTypes.html).

| Choice         | Common use                                | Check before deployment                             |
| -------------- | ----------------------------------------- | --------------------------------------------------- |
| A / AAAA       | IPv4 / IPv6 address                       | Address stability and TTL                           |
| CNAME          | Alias another name where DNS rules permit | Cannot be used at the zone apex                     |
| Route 53 alias | Supported AWS target or record            | Target support and health evaluation                |
| Weighted       | Controlled distribution or gradual shift  | Weights and independent target health               |
| Latency        | Route toward measured AWS Region          | Client resolver location may differ from user       |
| Failover       | Primary/secondary answers                 | Health checks, resolver cache and application retry |
| Geolocation    | Location-based answer selection           | Default record and unknown locations                |
| Multivalue     | Return a limited set of healthy answers   | Not a load balancer or application health proxy     |

```text
registrar/parent delegation → authoritative hosted zone
                                 ├─ public records → internet resolvers
                                 └─ private records → associated VPC resolvers
```

For a failover drill, prepare two endpoints with independent health checks and inspect their record policies. Query an authoritative name server and at least one recursive resolver before and after failure. Preserve each answer's TTL and record the actual client reconnection time. Route 53 can change the authoritative answer while a resolver or application still uses a cached result. A private zone also needs VPC DNS support/hostnames and an explicit association; VPC peering by itself does not expose the zone.

### Select a health-check type

| Type             | Input                                                        | Useful test                                                                      |
| ---------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| Endpoint         | Publicly reachable HTTP/HTTPS/TCP endpoint                   | Fail the synthetic `/health` response while leaving DNS unchanged                |
| Calculated       | Child check results and a healthy-child threshold            | With three checks and threshold two, fail one, then two; compare aggregate state |
| CloudWatch alarm | Supported alarm's metric data stream and evaluation criteria | Publish sandbox metric values that cross the configured threshold                |

Endpoint checkers run outside your VPC and cannot directly probe private IPs. For private application health, publish a suitable metric from an internal observer and use a supported alarm-based check. This check evaluates the alarm's underlying data, not simply its displayed ALARM state; manually setting alarm state is not an adequate end-to-end test. Missing-data treatment is an explicit choice. [Health-check type contract](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-types.html).

For endpoint checks, consecutive successes/failures apply at each checker, then Route 53 aggregates checker observations; this is not a universal "three out of three checkers" rule. Choose protocol/path, interval, failure threshold and allowed checker network access from [the configuration guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-creating-values.html). Record check state separately from DNS/client convergence and remove only dedicated lab checks after removing their record references.

### Blue/green example

Suppose two healthy application endpoints are behind weighted records. Begin with a small new-version weight, confirm the answer distribution over many independent DNS queries, then raise the weight only after application health and error budgets are acceptable. Cached DNS answers, resolver behavior and persistent connections mean request distribution need not exactly equal record weights over a short window. For a rollback, set the old endpoint's weight back and observe clients through at least the effective TTL and connection lifetime; do not report success from one `dig` response alone. A health-checked failover record is a separate routing choice with different behavior from a weighted canary.

## References

- [Route 53 concepts](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html).
- [Alias values and TTL](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-values-alias.html).
- [DNS failover](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html).
- [DNSSEC](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-configure-dnssec.html).
- [Pricing](https://aws.amazon.com/route53/pricing/).

## Across the wiki

- [[GCP/networking/cloud-dns/README|GCP Cloud DNS Architecture]] — DNS (GCP)
- [[Architecture/solution-architecture-concepts/software-engineering-concepts/dns/README|DNS]] — DNS (Architecture)
- [[Linux/networking/dns-resolution|DNS Resolution]] — DNS (Linux)
- [[Kubernetes/concepts/L04-services-networking/03-dns|DNS in Kubernetes]] — DNS (Kubernetes)
