---
title: EKS Troubleshooting
tags: [eks, troubleshooting, operations]
date: 2026-05-17
description: How to approach an EKS problem — a layered model for locating the fault, the first commands to run, where each kind of evidence lives, and links to symptom-specific playbooks.
---

# EKS Troubleshooting

An EKS problem can live in Kubernetes, in AWS, or in the seam between them. Most time is lost debugging the wrong layer: reading pod logs when a security group is closed, or inspecting IAM when a readiness probe is failing. Locate the layer first, then go deep.

## The layers

```
┌────────────────────────────────────────────────────────────────────┐
│ 5. Application      crashes, bad config, failing probes            │
│ 4. Kubernetes       scheduling, RBAC, quotas, admission, DNS       │
│ 3. Add-ons          VPC CNI, CoreDNS, kube-proxy, CSI, LB controller│
│ 2. Nodes            kubelet, containerd, disk, memory, kernel      │
│ 1. AWS              IAM, VPC routing, security groups, quotas, ENIs│
│ 0. Control plane    API server, etcd — managed by AWS              │
└────────────────────────────────────────────────────────────────────┘
```

Ask three questions in order:

1. **What changed?** A deployment, an add-on update, a node AMI, an IAM policy, a security group. Most incidents follow a change.
2. **What is the blast radius?** One pod, one node, one zone, one namespace, or everything? The scope points at the layer: one node suggests layers 1–2, everything suggests an add-on or the network.
3. **Does it reproduce outside the application?** A debug pod that cannot resolve DNS rules out the application at once.

## First five minutes

```bash
# Is the cluster itself healthy?
aws eks describe-cluster --name my-cluster --query 'cluster.{status:status,version:version,health:health}'
kubectl get --raw='/readyz?verbose' | tail -3

# Nodes and system add-ons
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide

# What is Kubernetes complaining about, most recent last?
kubectl get events -A --sort-by=.lastTimestamp | tail -30

# The failing workload
kubectl describe pod <pod> -n <ns>          # read Events at the bottom first
kubectl logs <pod> -n <ns> --previous       # the crashed container, not the new one
```

`kubectl describe` and events answer the majority of questions. Read them before forming a theory. The general method is in [[Kubernetes/concepts/L08-operations/01-troubleshooting|Kubernetes troubleshooting]] and [[Linux/troubleshooting/systematic-debugging|systematic debugging]].

## Where the evidence lives

| Evidence                                    | Where                                                                                                                   |
| :------------------------------------------ | :---------------------------------------------------------------------------------------------------------------------- |
| Pod and object state, events                | `kubectl describe`, `kubectl get events` (events expire after an hour)                                                  |
| Application logs                            | `kubectl logs`; your log backend for anything older — [[Kubernetes/eks/observability/logging/pod-logging\|pod logging]] |
| API server, audit, authenticator, scheduler | [[Kubernetes/eks/observability/logging/control-plane-logs\|Control plane logs]] in CloudWatch, if enabled               |
| kubelet and containerd                      | `journalctl -u kubelet` / `-u containerd` on the node ([[Linux/observability/journalctl\|journalctl]])                  |
| VPC CNI                                     | `/var/log/aws-routed-eni/ipamd.log` and `plugin.log` on the node                                                        |
| AWS API errors                              | [[AWS/security/cloudtrail/README\|CloudTrail]] — filter on `errorCode`                                                  |
| Dropped network traffic                     | VPC Flow Logs — look for `REJECT`                                                                                       |
| Add-on and node group health                | `aws eks describe-addon`, `aws eks describe-nodegroup` (`health.issues`)                                                |
| Cluster-level findings                      | EKS console → Cluster insights and Observability dashboard                                                              |

## Getting onto a node

Prefer Session Manager to SSH: no keys, no open port, and every session is logged.

```bash
aws ssm start-session --target i-0123456789abcdef0
```

When you cannot reach the node that way, a debug pod shares its namespaces:

```bash
kubectl debug node/ip-10-0-1-23.eu-west-1.compute.internal -it --image=public.ecr.aws/amazonlinux/amazonlinux:2023
chroot /host
```

For a container with no shell, attach an ephemeral container — [[Kubernetes/concepts/L08-operations/02-kubectl-debug|kubectl debug]]. Bottlerocket nodes have no shell by default; use its admin container.

For anything going to AWS Support, collect a bundle on the node with the **EKS log collector** script from the `awslabs/amazon-eks-ami` repository; it gathers kubelet, containerd, CNI, iptables and kernel output in one archive.

## Playbooks by symptom

| Symptom                                  | Go to                                                                          |
| :--------------------------------------- | :----------------------------------------------------------------------------- |
| Anything EKS-specific, as a lookup table | [[Kubernetes/eks/troubleshooting/common-issues\|Common EKS issues]]            |
| Pod stuck `Pending`                      | [[Kubernetes/guides/troubleshooting/pod-pending\|Pod Pending]]                 |
| `CrashLoopBackOff`                       | [[Kubernetes/guides/troubleshooting/crashloop-backoff\|CrashLoopBackOff]]      |
| `ImagePullBackOff`                       | [[Kubernetes/guides/troubleshooting/image-pull\|Image pull failures]]          |
| Node `NotReady`                          | [[Kubernetes/guides/troubleshooting/node-not-ready\|Node NotReady]]            |
| Service not reachable                    | [[Kubernetes/guides/troubleshooting/service-unreachable\|Service unreachable]] |
| DNS failures                             | [[Kubernetes/guides/troubleshooting/dns-resolution\|DNS resolution]]           |
| PVC stuck                                | [[Kubernetes/guides/troubleshooting/pvc-stuck\|PVC stuck]]                     |
| Ingress returns 404 or 503               | [[Kubernetes/guides/troubleshooting/ingress-404\|Ingress 404]]                 |
| Pod IP or ENI problems                   | [[Kubernetes/eks/networking/vpc-cni/troubleshooting\|VPC CNI troubleshooting]] |
| Access denied to the cluster             | [[Kubernetes/eks/security/access/README\|EKS access]]                          |
| Problems during or after an upgrade      | [[Kubernetes/eks/cluster-upgrades/upgrade-process\|Upgrade process]]           |

## Habits that shorten incidents

- **Enable control plane logging and a log backend before you need them.** Evidence that was never collected cannot be recovered.
- **Keep add-ons current.** A large share of "mysterious" issues are fixed bugs in the VPC CNI, CoreDNS or kube-proxy.
- **Alert on leading indicators**: free IPs per subnet, node disk pressure, CoreDNS errors, API server 5xx, pending pods.
- **Rehearse.** Run [[Kubernetes/guides/non-functional/chaos-engineering|chaos experiments]] for node loss and zone loss so the first time is not in production.
- **Write the postmortem** — [[DevOps/sre/incident-management|incident management]].

## Related

- [[Kubernetes/eks/troubleshooting/support-resources|Support resources]]
- [[Kubernetes/concepts/L08-operations/03-common-failure-modes|Common failure modes]]
- [[Kubernetes/troubleshooting|Kubernetes troubleshooting index]]
- [EKS troubleshooting guide](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)

## Across the wiki

- [[Azure/compute/aks/troubleshooting-runbook|AKS SRE Troubleshooting & Incident Runbook — CrashLoopBackOff, Node NotReady, and CNI Leaks]] — troubleshooting (Azure)
- [[GCP/compute/gke/troubleshooting-runbook|GKE SRE Incident Response & Production Troubleshooting Runbook]] — troubleshooting (GCP)
- [[Linux/troubleshooting/README|Linux Troubleshooting]] — troubleshooting (Linux)
