---
title: Karpenter on EKS
tags: [eks, compute, karpenter, autoscaling]
date: 2026-05-17
description: Operating Karpenter on EKS — NodePool and EC2NodeClass design, the AWS resources it depends on, consolidation and disruption budgets, Spot handling and common failure modes.
---

# Karpenter on EKS

Karpenter is a node autoscaler that launches EC2 instances directly, without Auto Scaling groups. It watches for unschedulable pods, works out the cheapest set of instances that satisfies their requirements, and launches them in well under a minute. It also removes and replaces nodes to keep the cluster cheap.

This page covers the AWS-specific side. For the scheduling model and how Karpenter compares in principle, see [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter (concepts)]] and [[Kubernetes/concepts/L06-scheduling-scaling/09-cluster-autoscaler|Cluster Autoscaler (concepts)]].

> [[Kubernetes/eks/compute/eks-auto-mode/README|EKS Auto Mode]] runs a managed Karpenter for you. If Auto Mode's constraints are acceptable, you do not need to install or operate anything on this page.

## What Karpenter needs in AWS

| Resource                   | Purpose                                                                                                                                                       |
| :------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Controller role            | Lets the controller call `ec2:CreateFleet`, `RunInstances`, `TerminateInstances`, read pricing and SSM                                                        |
| Node role and access entry | The [[AWS/security/iam/README\|IAM]] role instances assume; an access entry of type `EC2_LINUX` lets them join                                                |
| Discovery tags             | `karpenter.sh/discovery: <cluster>` on the subnets and security groups Karpenter may use                                                                      |
| Interruption queue         | An [[AWS/application-integration/sqs/README\|SQS]] queue fed by EventBridge rules for Spot interruptions, rebalance recommendations and scheduled maintenance |

The controller itself must not run on nodes it manages. Put it on a small managed node group or on [[Kubernetes/eks/compute/fargate/README|Fargate]].

## The two objects you write

A **NodePool** says what kind of capacity is allowed and how it may be disrupted. An **EC2NodeClass** says how to build the instance.

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: general
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64", "arm64"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]
      expireAfter: 720h
  limits:
    cpu: "1000"
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
    budgets:
      - nodes: "10%"
      - nodes: "0"
        schedule: "0 9 * * mon-fri"
        duration: 8h
        reasons: ["Drifted", "Underutilized"]
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: KarpenterNodeRole-my-cluster
  amiSelectorTerms:
    - alias: al2023@v20260901
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 80Gi
        volumeType: gp3
        encrypted: true
```

Design notes:

- **Keep requirements broad.** The more instance types Karpenter may choose from, the cheaper and more available the result, especially on Spot. Constrain by category and generation rather than listing types.
- **Pin the AMI.** `alias: al2023@latest` means every AMI release drifts and replaces every node. Pin a version and move it deliberately as part of an [[Kubernetes/eks/cluster-upgrades/upgrade-process|upgrade]].
- **Always set `limits`.** A runaway Deployment otherwise scales the bill without bound.
- **`expireAfter`** recycles nodes on a schedule, which is how you guarantee patch currency.

## Disruption: the part that causes incidents

Karpenter voluntarily removes nodes for three reasons:

| Reason            | Trigger                                                                                |
| :---------------- | :------------------------------------------------------------------------------------- |
| **Consolidation** | A node is empty, or its pods fit on other nodes or a cheaper replacement               |
| **Drift**         | The node no longer matches its NodePool or EC2NodeClass (new AMI, changed requirement) |
| **Expiration**    | The node is older than `expireAfter`                                                   |

Disruption respects [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudgets]] and the `karpenter.sh/do-not-disrupt: "true"` pod annotation. Three rules keep it safe:

1. Every service with more than one replica has a PDB. Without one, consolidation can drain all replicas at once.
2. Use NodePool **budgets** to cap how many nodes are disrupted simultaneously and to block disruption during business hours.
3. A PDB with `maxUnavailable: 0`, or a single-replica workload with `do-not-disrupt`, blocks the node forever. Expiration will eventually override it only if `terminationGracePeriod` is set on the NodePool.

## Spot

With both capacity types allowed, Karpenter prefers Spot and falls back to On-Demand when Spot is unavailable. It uses the price-capacity-optimized allocation strategy, so it picks pools that are cheap _and_ unlikely to be reclaimed. When the interruption queue is configured, a two-minute Spot warning makes Karpenter cordon, drain and replace the node immediately. More in [[Kubernetes/eks/compute/managed-node-groups/spot|Spot on EKS]].

To keep a baseline on On-Demand, run two NodePools with different `weight` values, or spread a workload across capacity types with a topology spread constraint on `karpenter.sh/capacity-type`.

## Troubleshooting

| Symptom                                           | Likely cause                                                                                                                                                                     |
| :------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pods stay `Pending`, no NodeClaim created         | No NodePool satisfies the pod's node selector, affinity or tolerations; or the NodePool hit its `limits`                                                                         |
| NodeClaim created, instance never joins           | Node role has no access entry, or the node cannot reach the cluster endpoint ([[Kubernetes/eks/security/access/endpoint-access\|endpoint access]])                               |
| `InsufficientInstanceCapacity` in controller logs | Requirements too narrow for the zone; widen instance families                                                                                                                    |
| Nodes churn constantly                            | AMI alias set to `latest`, or consolidation fighting an HPA — raise `consolidateAfter`                                                                                           |
| Pods `Pending` on IP exhaustion                   | Subnets are full — see [[Kubernetes/eks/networking/vpc-cni/prefix-delegation\|prefix delegation]] and [[Kubernetes/eks/networking/vpc-cni/custom-networking\|custom networking]] |

```bash
kubectl get nodepools,nodeclaims
kubectl describe nodeclaim <name>
kubectl logs -n kube-system deploy/karpenter -f
```

## Related

- [[Kubernetes/eks/compute/README|Compute options on EKS]]
- [[Kubernetes/eks/advanced/autoscaling|Autoscaling on EKS]] and [[Kubernetes/eks/advanced/cost-optimization|cost optimization]]
- [[Kubernetes/eks/compute/managed-node-groups/graviton|Graviton]] — mixing architectures in one NodePool
- [[AWS/cost-management/ec2-cost-optimization|EC2 cost optimization]]
- [Karpenter documentation](https://karpenter.sh/docs/)

## Across the wiki

- [[Azure/compute/aks/autoscaling-keda|AKS Autoscaling Architecture — Cluster Autoscaler, KEDA, and Virtual Nodes]] — autoscaling (Azure)
- [[GCP/compute/gke/autoscaling|GKE Autoscaling Architecture — Cluster Autoscaler, NAP, HPA v2, and VPA]] — autoscaling (GCP)
- [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/scalability|Scalability]] — autoscaling (Architecture)
