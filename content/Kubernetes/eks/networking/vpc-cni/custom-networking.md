---
title: VPC CNI Custom Networking
tags: [eks, networking, vpc-cni, custom-networking, ip-management]
date: 2026-05-17
description: Using VPC CNI custom networking to place pods in different subnets and security groups from their nodes — when it is needed, ENIConfig per zone, the effect on pod density, rollout steps and pitfalls.
---

# VPC CNI Custom Networking

By default the [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]] gives pods IP addresses from the **same subnet as their node**, with the node's security groups. Custom networking breaks that link: pods get their addresses from subnets you nominate, and can use different security groups from the node.

## Why you would want it

| Problem                                           | How custom networking helps                                                                                          |
| :------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------- |
| **The VPC is running out of routable addresses**  | Put pods in a secondary CIDR such as `100.64.0.0/10`, leaving the scarce routable range for nodes and load balancers |
| **Pods and nodes need different security groups** | Pod ENIs use the groups named in the `ENIConfig`                                                                     |
| **Pods must sit in dedicated subnets**            | Separate route tables: for example pods egress through a specific NAT or firewall                                    |
| **Overlapping CIDRs with other networks**         | Only node subnets are advertised; pod ranges stay private and are SNATed                                             |

IP exhaustion is by far the most common reason. The alternatives are compared in [[Kubernetes/eks/advanced/advanced-networking|advanced EKS networking]].

## How it works

```
node in subnet 10.0.1.0/24 (routable)
├── primary ENI   10.0.1.37         ← the node itself; NOT used for pods
├── secondary ENI 100.64.12.0/19    ← from the ENIConfig for this zone
│     └── pod IPs 100.64.12.x
└── secondary ENI 100.64.12.0/19
      └── pod IPs 100.64.12.y
```

An `ENIConfig` custom resource names a subnet and security groups. Each node is matched to one `ENIConfig`, normally by its Availability Zone, and every **secondary** ENI is created from it. The primary ENI stays in the node subnet and no longer carries pods.

## Set it up

**1. Add a secondary CIDR and subnets** — one per zone, with routes to a NAT gateway if pods need outbound access:

```bash
aws ec2 associate-vpc-cidr-block --vpc-id vpc-0abc --cidr-block 100.64.0.0/16
```

**2. Enable custom networking** and tell the CNI to match by zone:

```bash
aws eks update-addon --cluster-name my-cluster --addon-name vpc-cni \
  --configuration-values '{"env":{
    "AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG":"true",
    "ENI_CONFIG_LABEL_DEF":"topology.kubernetes.io/zone"}}'
```

**3. Create one `ENIConfig` per zone**, named exactly after the zone:

```yaml
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: eu-west-1a
spec:
  subnet: subnet-0aaa1111bbbb2222c # 100.64.0.0/19 in eu-west-1a
  securityGroups:
    - sg-0ddd3333eeee4444f
```

**4. Replace the nodes.** The setting only applies to ENIs attached after it is enabled, so existing nodes must be recycled.

## The effect on pod density

Because the primary ENI no longer hosts pods, each node loses one ENI's worth of addresses:

```
max pods = (ENIs − 1) × (IPs per ENI − 1) + 2

m5.large: 3 ENIs, 10 IPs each
  default:            3 × 9 + 2 = 29
  custom networking:  2 × 9 + 2 = 20
```

Small instances are hit hardest. Two consequences:

- **Set `maxPods` to match.** Managed node groups without a custom launch template calculate it for you; with a custom AMI or launch template you must pass the lower value, or the scheduler places pods that can never get an IP.
- **Combine with [[Kubernetes/eks/networking/vpc-cni/prefix-delegation|prefix delegation]].** Assigning /28 prefixes instead of single addresses more than recovers the loss — an `m5.large` goes to 110 pods — and the `100.64.0.0/10` space has plenty of room for prefixes.

## Traffic behaviour

- **Pod to pod** within the VPC is routed directly; the secondary CIDR is part of the VPC.
- **Pod to outside the VPC** is source-NATed to the node's primary IP by default, so on-premises networks and peered VPCs see node addresses and never need a route to `100.64.0.0/10`. That is what makes the non-routable range workable.
- If pod subnets have their own NAT gateway and you want traffic to leave from the pod's address instead, set `AWS_VPC_K8S_CNI_EXTERNALSNAT=true`.
- **Load balancers with IP targets** register pod addresses, so the load balancer subnets need a route to the pod subnets — true inside one VPC.

## Pitfalls

| Pitfall                                                   | Result                                                               |
| :-------------------------------------------------------- | :------------------------------------------------------------------- |
| No `ENIConfig` for a zone that has nodes                  | Nodes there stay `NotReady`; pods get no IPs                         |
| `ENIConfig` name does not match the zone label            | Same                                                                 |
| Nodes not replaced after enabling                         | Old nodes keep using node subnets; behaviour is inconsistent         |
| `maxPods` left at the default                             | Pods stuck `ContainerCreating` with "failed to assign an IP address" |
| Pod security group lacks rules the node group had         | DNS, probes or load balancer health checks fail                      |
| Pod subnets without a NAT route                           | Image pulls and AWS API calls time out                               |
| A security group shared between node and pod ENIs changes | Affects both; keep them separate if they should differ               |

On [[Kubernetes/eks/compute/eks-auto-mode/README|Auto Mode]] the same outcome is configured on the `NodeClass` (`podSubnetSelectorTerms`) rather than with `ENIConfig`.

## Checking it

```bash
kubectl get eniconfigs
kubectl get nodes -L topology.kubernetes.io/zone
kubectl get pods -A -o wide | awk '{print $7}' | sort | uniq -c | head   # pod IPs should be in 100.64.x.x
kubectl describe node <node> | grep -i "pods\|eniconfig"
```

Address pools and warm targets are explained in [[Kubernetes/eks/networking/vpc-cni/eni-allocation|ENI allocation]]; failures in [[Kubernetes/eks/networking/vpc-cni/troubleshooting|VPC CNI troubleshooting]].

## Related

- [[Kubernetes/eks/networking/README|EKS networking overview]]
- [[Kubernetes/eks/networking/vpc-cni/configuration-reference|VPC CNI configuration reference]]
- [[Kubernetes/eks/networking/vpc-cni/security-groups-for-pods|Security groups for pods]] — per-pod rather than per-node-pool groups
- [[AWS/networking/vpc/README|Amazon VPC]] and [[Architecture/solution-architecture-concepts/networking/nat|NAT]]
- [Custom networking for pods](https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html)
