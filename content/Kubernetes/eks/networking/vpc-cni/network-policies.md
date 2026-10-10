---
title: Network Policies with the VPC CNI
tags: [eks, networking, vpc-cni, network-policy, security]
date: 2026-05-17
description: Enforcing Kubernetes NetworkPolicy natively with the Amazon VPC CNI — the eBPF architecture, how to enable it, enforcement modes, interaction with security groups, limitations and debugging.
---

# Network Policies with the VPC CNI

By default every pod in an EKS cluster can talk to every other pod. [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]] is the Kubernetes API for restricting that, but the API does nothing unless the CNI enforces it. The Amazon [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]] has enforced it natively since version 1.14, so a separate policy engine such as Calico is no longer required.

## How enforcement works

```
NetworkPolicy ──► Network Policy Controller ──► PolicyEndpoint (CRD)
 (you write)        (EKS control plane)              │
                                                     ▼
                              aws-network-policy-agent (in the aws-node pod, every node)
                                                     │
                                                     ▼
                              eBPF programs on each pod's veth, ingress and egress
```

- The **controller** runs in the managed control plane. It resolves pod and namespace selectors into concrete IPs and writes `PolicyEndpoint` objects.
- The **node agent** is a container in the `aws-node` DaemonSet. It attaches [[Observability/ebpf|eBPF]] programs to the host side of each selected pod's veth pair and keeps allowed peers in eBPF maps.
- Enforcement happens in the kernel on the node, not in [[Linux/networking/iptables|iptables]], so it scales with the number of policies better than rule chains do.

Requirements: Linux nodes with kernel 5.10 or later (all current EKS-optimized AMIs qualify), and the VPC CNI managed as an add-on at 1.14 or newer.

## Enable it

```bash
aws eks update-addon \
  --cluster-name my-cluster \
  --addon-name vpc-cni \
  --configuration-values '{"enableNetworkPolicy":"true"}'
```

Verify that each `aws-node` pod now runs two containers and that the CRD exists:

```bash
kubectl get ds aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[*].name}'
kubectl get crd policyendpoints.networking.k8s.aws
```

On [[Kubernetes/eks/compute/eks-auto-mode/README|Auto Mode]], network policy is switched on through the `NodeClass` and a ConfigMap rather than the add-on.

## A baseline that works

Start each namespace with default-deny, then open what is needed. Remember DNS — forgetting it is the classic self-inflicted outage.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: payments
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: payments
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: kube-system }
          podSelector:
            matchLabels: { k8s-app: kube-dns }
      ports:
        - { protocol: UDP, port: 53 }
        - { protocol: TCP, port: 53 }
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-from-ingress
  namespace: payments
spec:
  podSelector:
    matchLabels: { app: api }
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: ingress }
      ports:
        - { protocol: TCP, port: 8080 }
```

## Enforcement mode: standard or strict

There is a short window between a pod starting and its policies being programmed. The `NETWORK_POLICY_ENFORCING_MODE` setting decides what happens in it:

| Mode       | New pod before policies are applied | Trade-off                                                    |
| :--------- | :---------------------------------- | :----------------------------------------------------------- |
| `standard` | Allow all                           | Default. Brief window where a new pod is unrestricted        |
| `strict`   | Deny all                            | No window, but every pod needs a policy or it has no network |

Use `strict` only when compliance demands it, and make sure system namespaces have policies first.

## Network policies and security groups

They work at different layers and both apply:

| Control                                                                                  | Scope                          | Identifies peers by    |
| :--------------------------------------------------------------------------------------- | :----------------------------- | :--------------------- |
| NetworkPolicy                                                                            | Pod to pod, inside the cluster | Labels and namespaces  |
| [[AWS/networking/vpc/security-groups\|Security groups]] on nodes                         | Node ENIs                      | Security group or CIDR |
| [[Kubernetes/eks/networking/vpc-cni/security-groups-for-pods\|Security groups for pods]] | Individual pod ENIs            | Security group or CIDR |

Use NetworkPolicy for east-west segmentation between workloads, and security groups for the boundary to AWS resources such as RDS, where the peer is not a pod. Traffic must be allowed by every layer it crosses.

## Limitations

- **Pods only.** Policies apply to pod IPs. Pods with `hostNetwork: true` are governed by the node's security groups instead.
- **No Fargate or Windows** nodes.
- **Standard API only by default.** No L7 rules. FQDN-based egress rules and cluster-wide admin policies have arrived through newer AWS-specific and upstream APIs; check the add-on version you run before relying on them. If you need rich L7 policy today, [[Kubernetes/concepts/L04-services-networking/06-cni|Cilium]] is the usual alternative.
- **Egress to AWS services** such as S3 has to be expressed as CIDR blocks, which change. Prefer [[AWS/networking/vpc/README|VPC endpoints]] with a security group, and allow the endpoint's CIDR.
- **Load balancer health checks** to pods with IP targets come from the VPC, not from a pod. Allow the VPC CIDR (or the load balancer subnets) with an `ipBlock` rule or health checks fail and the target is drained.

## Debugging

```bash
# Which policies select this pod, and what did they resolve to?
kubectl get networkpolicy -n payments
kubectl get policyendpoints -n payments -o yaml

# Agent logs on the node that runs the pod
kubectl logs -n kube-system <aws-node-pod> -c aws-eks-nodeagent
```

Setting `enablePolicyEventLogs` in the add-on configuration logs every allow and deny decision with source, destination, port and verdict; `enableCloudWatchLogs` ships them to [[AWS/monitoring/cloudwatch-logs/README|CloudWatch Logs]]. Turn it on while developing policies and off again afterwards — it is verbose.

| Symptom                                 | Usual cause                                                                  |
| :-------------------------------------- | :--------------------------------------------------------------------------- |
| Everything times out after default-deny | DNS egress not allowed                                                       |
| Target group shows pods unhealthy       | Health-check source CIDR not allowed                                         |
| Policy has no effect                    | `enableNetworkPolicy` not set, or the pod uses host networking               |
| Works on some nodes only                | Mixed CNI versions during an upgrade; check the agent container on each node |

## Related

- [[Kubernetes/eks/networking/README|EKS networking overview]]
- [[Kubernetes/eks/networking/vpc-cni/troubleshooting|VPC CNI troubleshooting]]
- [[Security/kubernetes-security/network-policies/README|Network policies (Security section)]]
- [[Security/zero-trust|Zero trust]] — the principle default-deny implements
- [Kubernetes network policies on EKS](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html)
