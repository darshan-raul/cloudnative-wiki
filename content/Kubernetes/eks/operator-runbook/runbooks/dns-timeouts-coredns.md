---
title: "Runbook: DNS Timeouts and Intermittent Resolution Failures"
description: "Pods see 'i/o timeout' or EAI_AGAIN on DNS lookups, or 5-second latency spikes. Find whether CoreDNS, the VPC resolver's packet limit, conntrack or policy is dropping queries."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    dns,
    coredns,
    networking,
    incident,
  ]
date: 2026-10-20
aliases: [EKS CoreDNS timeouts runbook, EKS intermittent DNS]
---

# Runbook: DNS Timeouts and Intermittent Resolution Failures

**Applies to:** EKS clusters running CoreDNS (the `coredns` add-on) on EC2 nodes with the VPC CNI.
**Typical severity:** Sev 1–2. DNS failures surface as errors in every service at once and look like an application outage.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

- Application errors like:

  ```text
  dial tcp: lookup orders.prod.svc.cluster.local on 172.20.0.10:53: read udp 10.0.12.7:40521->172.20.0.10:53: i/o timeout
  getaddrinfo EAI_AGAIN api.example.com
  ```

- Latency spikes of almost exactly **5 seconds** (the default resolver retry timeout) on a fraction of requests.
- CoreDNS logs `[ERROR] plugin/errors: 2 api.example.com. A: read udp ...->10.0.0.2:53: i/o timeout`. That's an upstream (VPC resolver) timeout.
- Worse during traffic peaks, large rollouts, or Karpenter consolidation.

## Impact

Every lookup goes through CoreDNS, so partial DNS loss means partial failure everywhere. Clients that cache poorly, such as many runtimes and especially short-lived processes, amplify it.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export KUBE_DNS=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
```

## Triage

**1. Reproduce from inside the cluster.** Use the Kubernetes DNS test image:

```bash
kubectl run dnsutils -n default --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 \
  --restart=Never -- sleep 3600
kubectl exec dnsutils -- cat /etc/resolv.conf
kubectl exec dnsutils -- sh -c "fails=0; for i in \$(seq 1 200); do dig +short +tries=1 +time=1 amazon.com @$KUBE_DNS >/dev/null || fails=\$((fails+1)); done; echo failures=\$fails/200"
kubectl exec dnsutils -- sh -c "fails=0; for i in \$(seq 1 200); do dig +short +tries=1 +time=1 kubernetes.default.svc.cluster.local @$KUBE_DNS >/dev/null || fails=\$((fails+1)); done; echo failures=\$fails/200"
```

- **Expect:** 0 failures for both.
- **If** only external names fail → upstream path (cause B) or `ndots` amplification (cause C).
- **If** both fail → CoreDNS capacity or health (cause A), conntrack (cause D), or policy (cause E).
- **If** the test Pod is fine but the application isn't → compare the application Pod's `resolv.conf`, its node, its NetworkPolicy and its security group (cause E).

**2. Is CoreDNS healthy and big enough?**

```bash
kubectl get deploy coredns -n kube-system
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl top pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=200 | grep -E 'ERROR|timeout|SERVFAIL' | tail -20
```

Two replicas (the default) is too few for hundreds of nodes or high query rates. Look for restarts, CPU throttling and replicas packed onto one node.

**3. Is the VPC resolver dropping packets?** The Amazon-provided DNS resolver allows **1,024 packets per second per network interface**. All CoreDNS upstream traffic from one node counts against that node's ENI. Check on each node running CoreDNS (`aws ssm start-session --target <instance>`):

```bash
ethtool -S eth0 | grep -E 'linklocal_allowance_exceeded|conntrack_allowance_exceeded|pps_allowance_exceeded'
```

- **If** `linklocal_allowance_exceeded` is non-zero and growing → upstream packet limit (cause B).

**4. Is conntrack dropping UDP?** On the client node:

```bash
sudo conntrack -S | grep -o 'insert_failed=[0-9]*' | sort | uniq -c
sudo sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
```

- **If** `insert_failed` grows, or the count is near the max → cause D.

**5. CoreDNS metrics**, if you scrape port 9153: request rate (`coredns_dns_requests_total`), `SERVFAIL` rate (`coredns_dns_responses_total{rcode="SERVFAIL"}`) and upstream latency (`coredns_forward_request_duration_seconds`).

## Diagnosis

| Signal                                                                   | Cause                                          | Fix   |
| ------------------------------------------------------------------------ | ---------------------------------------------- | ----- |
| CoreDNS CPU-bound, throttled, restarting, or too few replicas            | A. CoreDNS under-provisioned                   | Fix A |
| `linklocal_allowance_exceeded` rising; upstream timeouts in CoreDNS logs | B. VPC resolver packet limit                   | Fix B |
| External names fail; query rate many times the request rate              | C. `ndots:5` search-path amplification         | Fix C |
| 5 s spikes; `insert_failed` rising                                       | D. conntrack race or exhaustion                | Fix D |
| One namespace or Pod group only                                          | E. NetworkPolicy or security group blocking 53 | Fix E |
| Spikes line up with CoreDNS Pods terminating                             | F. CoreDNS disrupted by scale-in or rollout    | Fix F |

## Fix

### A. CoreDNS under-provisioned

Scale it out, and spread it. With the managed add-on (CoreDNS v1.9 and later), EKS can autoscale CoreDNS for you. It sets replicas to the larger of nodes ÷ 16 and CPU cores ÷ 256, scales up quickly, and scales down by a third every 3 minutes. `minReplicas` and `maxReplicas` are optional bounds; keep the minimum above 2.

```bash
aws eks describe-addon-configuration --addon-name coredns --addon-version <version> \
  --query configurationSchema --output text | jq '.properties | keys'
aws eks update-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name coredns \
  --configuration-values '{"autoScaling":{"enabled":true,"minReplicas":4,"maxReplicas":20}}' \
  --resolve-conflicts PRESERVE
```

The first command confirms your add-on version's schema has `autoScaling`. On a self-managed CoreDNS, set the replica count yourself, or run the cluster-proportional-autoscaler. Make sure the replicas spread across nodes and AZs (`topologySpreadConstraints` in the same configuration).

**Undo:** re-apply the previous `configurationValues`.

### B. VPC resolver packet limit

More CoreDNS replicas **on more nodes** spread the per-ENI limit. Cut upstream traffic as well:

- Raise the CoreDNS `cache` TTL for external names (the default Corefile caches 30 s).
- Deploy NodeLocal DNSCache. It caches on every node, so each node's ENI carries its own share of upstream traffic.
- Fix `ndots` (Fix C). It's often most of the upstream volume.

### C. `ndots:5` amplification

With `ndots:5`, a lookup for `api.example.com` first tries `api.example.com.<ns>.svc.cluster.local`, `.svc.cluster.local`, `.cluster.local` and the VPC search domain (for example `ec2.internal`), each for A **and** AAAA. That's up to 10 queries per name. For workloads that mostly call external names:

```yaml
spec:
  dnsConfig:
    options:
      - name: ndots
        value: "2"
```

Alternatively, use fully qualified names with a trailing dot (`api.example.com.`) in client configuration.

### D. conntrack race or exhaustion

Parallel A and AAAA queries over one UDP socket can lose a race in conntrack and drop a packet. The client then waits out its 5-second timeout. Fixes:

- NodeLocal DNSCache. It answers on a link-local address without the DNAT race, and talks to CoreDNS over TCP.
- For glibc-based images, `dnsConfig` option `single-request-reopen`. Alpine and musl ignore it.
- If `nf_conntrack_count` is near the max, raise `nf_conntrack_max` through node configuration (an AL2023 `NodeConfig` or a Bottlerocket setting), and find the connection-heavy workload.

### E. Policy blocking DNS

- **NetworkPolicy:** any egress policy on the namespace must allow UDP **and** TCP 53 to `kube-system` Pods labelled `k8s-app: kube-dns`.
- **Security groups for Pods:** Pods with their own security group need outbound UDP and TCP 53 to the CoreDNS Pods. That means the node security group, or the CoreDNS Pods' security group if they have one.

```bash
kubectl get networkpolicy -n <namespace> -o yaml | grep -A20 egress
```

### F. CoreDNS disrupted by scale-in or rollout

Make sure CoreDNS has a PodDisruptionBudget (`kubectl get pdb -n kube-system`) and that the Corefile `health` plugin has a `lameduck` period (for example `lameduck 5s`). That way terminating replicas stop receiving traffic before they exit. Run CoreDNS on stable capacity rather than Spot nodes that consolidate often.

## Verify recovery

Re-run the 200-query loops from Triage step 1: **0 failures** for internal and external names, from the test Pod and from an affected application Pod. Confirm `linklocal_allowance_exceeded` and `insert_failed` stop increasing. Then delete the test Pod: `kubectl delete pod dnsutils`.

## Escalate

Open an AWS Support case if the VPC resolver itself returns errors or times out while `linklocal_allowance_exceeded` stays flat. That points at Route 53 Resolver, a Resolver rule, or an outbound endpoint (for hybrid DNS). Attach the VPC ID, resolver rule IDs, and timestamps of failing queries.

## Prevent

- Alert on CoreDNS `SERVFAIL` rate, upstream latency p99, and the `linklocal_allowance_exceeded` counter from the CloudWatch agent or node exporter.
- Size CoreDNS from the start: autoscaling, at least one replica per AZ, a PDB, and stable nodes.
- Run NodeLocal DNSCache on large or DNS-heavy clusters.
- Set `ndots` deliberately for workloads with heavy external lookups.

## Background

- [[Kubernetes/guides/troubleshooting/dns-resolution|Troubleshooting DNS resolution]]
- [[Kubernetes/concepts/L04-services-networking/03-dns|Kubernetes DNS]]
- [[Linux/networking/dns-resolution|DNS resolution on Linux]]
- [Amazon EKS best practices: monitoring CoreDNS traffic](https://docs.aws.amazon.com/eks/latest/best-practices/monitoring_eks_workloads_for_network_performance_issues.html)
