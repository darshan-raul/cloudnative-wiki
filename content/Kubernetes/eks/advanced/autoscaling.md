---
title: Autoscaling on EKS
tags: [eks, autoscaling, hpa, keda, karpenter, advanced]
date: 2026-05-17
description: How the autoscaling layers on EKS fit together — HPA, VPA and KEDA for pods, Karpenter or Cluster Autoscaler for nodes — with the end-to-end timeline of a scale-up, how to shorten it, conflicts to avoid and patterns for scale-to-zero and headroom.
---

# Autoscaling on EKS

Autoscaling on Kubernetes is not one feature. It is two independent control loops stacked on top of each other, and most scaling problems come from one loop working while the other does not, or from the two working against each other.

```
load ──► pod autoscaler decides MORE PODS ──► scheduler cannot place them ──► node autoscaler adds NODES
         (HPA / KEDA / VPA)                    (pods Pending)                  (Karpenter / Cluster Autoscaler / Auto Mode)
```

## The layers

| Layer | Tool                                                                                                                | Changes                           | Reacts to                                  |
| :---- | :------------------------------------------------------------------------------------------------------------------ | :-------------------------------- | :----------------------------------------- |
| Pods  | [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler\|HPA]]                                      | Replica count                     | CPU, memory, custom and external metrics   |
| Pods  | [[Kubernetes/concepts/L06-scheduling-scaling/10-keda\|KEDA]]                                                        | Replica count, including to zero  | Events: queue depth, stream lag, schedules |
| Pods  | [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler\|VPA]]                                      | CPU and memory requests           | Observed usage over time                   |
| Nodes | [[Kubernetes/eks/compute/karpenter/README\|Karpenter]] / [[Kubernetes/eks/compute/eks-auto-mode/README\|Auto Mode]] | Instances, chosen per pending pod | Unschedulable pods                         |
| Nodes | [[Kubernetes/eks/compute/managed-node-groups/cluster-autoscaler\|Cluster Autoscaler]]                               | Size of node groups               | Unschedulable pods                         |

The node layer responds **only to pods that cannot be scheduled**. It knows nothing about load. If the pod layer does not ask for more pods, no nodes are added, however hot the existing ones run.

## Everything depends on requests

Both layers reason about **requests**, not actual usage:

- HPA's CPU target is a percentage _of the request_. A pod with no CPU request cannot be scaled on CPU at all.
- The scheduler and the node autoscaler pack nodes by requests. Requests far above real usage mean half-empty nodes; requests far below it mean overloaded nodes that the autoscaler considers full of room.

Getting requests right is the first tuning step, before any autoscaler setting. See [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|requests and limits]]; VPA in recommendation mode is a good way to find sensible values.

## The timeline of a scale-up

| Step                                              | Typical duration   |
| :------------------------------------------------ | :----------------- |
| Metric scraped and visible to HPA                 | 15–60 s            |
| HPA evaluates and raises replicas                 | up to 15 s         |
| Scheduler marks the new pods unschedulable        | seconds            |
| Karpenter launches an instance                    | 30–60 s            |
| (Cluster Autoscaler + Auto Scaling group instead) | 1–3 min            |
| Node boots, joins, CNI ready                      | 20–60 s            |
| Image pull                                        | seconds to minutes |
| Application start and readiness                   | seconds to minutes |

End to end, new capacity for a traffic spike takes **one to five minutes**. If your traffic doubles faster than that, autoscaling alone will not save you.

## Shortening it

| Lever                             | How                                                                                                                                                                                                                                                  |
| :-------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Scale on a leading signal**     | Requests per second or queue depth rise before CPU does. Use custom metrics or KEDA.                                                                                                                                                                 |
| **Lower the HPA target**          | A 50–60% CPU target leaves room to absorb load while new pods start                                                                                                                                                                                  |
| **Headroom pods**                 | Low-priority placeholder pods reserve spare capacity; real pods preempt them instantly and the placeholders trigger new nodes in the background — [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption\|priority and preemption]] |
| **Faster nodes**                  | Karpenter over Cluster Autoscaler; Bottlerocket or minimal AMIs; avoid heavy user data                                                                                                                                                               |
| **Smaller images, or pre-pulled** | [[Containers/images-and-layers\|Image size]] is often the largest single delay                                                                                                                                                                       |
| **Fast, honest readiness**        | Slow start-up and long initial delays hold traffic back — [[Kubernetes/concepts/L03-workloads/10-probes\|probes]]                                                                                                                                    |
| **Scheduled scaling**             | For predictable peaks, raise `minReplicas` ahead of time with KEDA's cron scaler                                                                                                                                                                     |
| **Tune HPA behaviour**            | Scale up aggressively, scale down slowly                                                                                                                                                                                                             |

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: checkout
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: checkout }
  minReplicas: 4
  maxReplicas: 60
  metrics:
    - type: Resource
      resource:
        { name: cpu, target: { type: Utilization, averageUtilization: 60 } }
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies: [{ type: Percent, value: 100, periodSeconds: 30 }]
    scaleDown:
      stabilizationWindowSeconds: 300
      policies: [{ type: Percent, value: 20, periodSeconds: 60 }]
```

## Event-driven scaling and scale to zero

HPA cannot go below one replica. KEDA can, which suits queue workers and anything idle most of the day:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: order-worker
spec:
  scaleTargetRef: { name: order-worker }
  minReplicaCount: 0
  maxReplicaCount: 50
  triggers:
    - type: aws-sqs-queue
      authenticationRef: { name: keda-aws }
      metadata:
        queueURL: https://sqs.eu-west-1.amazonaws.com/111122223333/orders
        queueLength: "20"
        awsRegion: eu-west-1
```

KEDA reads the queue with its own IAM role ([[Kubernetes/eks/security/pod-identity|Pod Identity]]), creates an HPA behind the scenes, and combined with Karpenter the nodes disappear too when nothing is running. Scaling from zero pays the full cold-start timeline above, so use it where a delay of a minute or two is acceptable.

## Conflicts to avoid

| Combination                                                                                               | Problem                                                                                        | Resolution                                                                       |
| :-------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------- |
| HPA and VPA both on CPU or memory                                                                         | VPA changes requests, which changes HPA's utilisation, which changes replicas — they oscillate | HPA on a custom metric with VPA on resources, or VPA in recommendation-only mode |
| HPA and a manifest that sets `replicas`                                                                   | Every deployment resets the count                                                              | Omit `replicas` from the manifest; tell GitOps to ignore the field               |
| Node consolidation and an HPA that flaps                                                                  | Nodes are removed just before pods return                                                      | Longer scale-down stabilisation and `consolidateAfter`                           |
| Aggressive scale-down without [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget\|PDBs]] | Node removal evicts too many replicas at once                                                  | A PDB on every multi-replica workload                                            |
| Two autoscalers managing the same nodes                                                                   | They fight over the same capacity                                                              | One node autoscaler per set of nodes                                             |

## Limits and guardrails

Autoscaling without bounds is a way to turn a bug into a large bill.

- Set `maxReplicas` deliberately, and NodePool `limits` or node group `maxSize`.
- Check **quotas**: EC2 vCPU limits per instance family, and free IP addresses per subnet — running out of pod IPs is a common ceiling on EKS ([[Kubernetes/eks/networking/vpc-cni/eni-allocation|ENI allocation]]).
- Remember downstream limits. Scaling the API tier tenfold moves the bottleneck to the database connection limit.
- Alert on pods `Pending` for more than a few minutes and on HPAs pinned at `maxReplicas` — both mean scaling has hit a wall.

## Checking that it works

```bash
kubectl get hpa -A                                  # current vs target, and replicas
kubectl describe hpa checkout                       # events explain each decision
kubectl get pods --field-selector=status.phase=Pending -A
kubectl get nodeclaims                              # Karpenter's view
kubectl top pods -n payments
```

Then prove it under load: run a load test that doubles traffic, and time each step of the table above. See [[Kubernetes/guides/non-functional/auto-scaling|the auto-scaling guide]] and [[Architecture/solution-architecture-concepts/performance-testing|performance testing]].

## Related

- [[Kubernetes/eks/advanced/README|Advanced EKS topics]]
- [[Kubernetes/eks/advanced/cost-optimization|Cost optimization]] — the other side of the same settings
- [[Kubernetes/eks/compute/managed-node-groups/spot|Spot on EKS]]
- [[Kubernetes/eks/observability/metrics/prometheus|Prometheus on EKS]] — the source of custom metrics
- [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling|Scaling (concepts)]]

## Across the wiki

- [[Azure/compute/aks/autoscaling-keda|AKS Autoscaling Architecture — Cluster Autoscaler, KEDA, and Virtual Nodes]] — autoscaling (Azure)
- [[GCP/compute/gke/autoscaling|GKE Autoscaling Architecture — Cluster Autoscaler, NAP, HPA v2, and VPA]] — autoscaling (GCP)
- [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/scalability|Scalability]] — autoscaling (Architecture)
