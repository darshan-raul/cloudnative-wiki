---
title: Amazon EKS
description: Select an EKS operating model and follow the canonical Kubernetes track for access, networking, identity, upgrades and workload operations.
tags:
  - cloud/aws/compute
  - platform-engineering/kubernetes/eks
date: 2026-10-12
---

# Amazon EKS

EKS provides a managed Kubernetes control plane. Select an operating model from managed/self-managed nodes, Fargate and supported Auto Mode capabilities based on workload constraints and operational ownership. This AWS page is the service-selection overview; [[Kubernetes/eks/README|the EKS track]] owns detailed implementation lessons.

## Learning route

1. Start with [[Kubernetes/eks/README|EKS fundamentals]] and establish cluster/account access.
2. Use [[Kubernetes/eks/security/access/cluster-access-management|cluster access management]]; distinguish AWS authentication from Kubernetes authorization.
3. Choose [[Kubernetes/eks/security/pod-identity|Pod Identity]] or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]] for workload credentials. A node role is not a least-privilege identity for every pod.
4. Study [[Kubernetes/eks/advanced/advanced-networking|networking]] and address capacity before scaling.
5. Use [[Kubernetes/eks/advanced/autoscaling|current autoscaling guidance]], not legacy Karpenter Provisioner examples.
6. Plan [[Kubernetes/eks/cluster-upgrades/upgrade-process|upgrades]] and [[Kubernetes/eks/observability/README|observability]] before production adoption.

## Important boundaries

The AWS VPC CNI uses VPC networking; it does not universally require VXLAN port 8472. Follow [cluster security-group requirements](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html) rather than opening guessed ports. Check pod IP availability, subnet capacity, DNS and endpoint reachability when nodes or pods fail.

Standard managed add-ons are **not automatically upgraded** with a cluster minor-version upgrade. Review [add-on compatibility](https://docs.aws.amazon.com/eks/latest/userguide/updating-an-add-on.html), test and initiate updates. Version support and managed operations do not remove your workload-upgrade responsibility.

Pod Identity, IRSA and Container Insights are different features: credentials, credentials and telemetry respectively. Enabling telemetry does not create workload permissions.

## Cost exercise

Specify Region, cluster support tier, node model, node counts, instance prices, EBS, load balancers, public addresses, telemetry and transfer. For a hypothetical us-east-1 study dated 2026-10-12, assume a \$0.10/hour control plane plus six \$0.267/hour nodes over 730 hours: 730 × (\$0.10 + 6 × \$0.267) = \$1,242.46 before the other components. These inputs are study assumptions; use [EKS pricing](https://aws.amazon.com/eks/pricing/) and current instance prices for the selected model.

Fargate charges provisioned resources and duration, not Kubernetes limits multiplied by an arbitrary requests-per-month figure. Auto Mode has separately priced management dimensions.

## Read-only checkpoint

With an existing sandbox cluster, use `aws eks describe-cluster --name YOUR_CLUSTER` and `aws eks list-addons --cluster-name YOUR_CLUSTER`. Compare control-plane version, support tier, endpoint access and add-on versions with your upgrade plan. Run `kubectl auth can-i` to check Kubernetes permissions; do not assume an AWS administrator identity has the desired cluster RBAC.

Follow the canonical track's lab cleanup for nodes, services/load balancers, volumes and cluster. Deleting a Kubernetes object is not evidence that all external resources have been removed.

## Cluster architecture and capacity options

```text
AWS managed Kubernetes API and etcd
                 │
          Kubernetes scheduler
                 │
    ┌────────────┼────────────┐
 managed nodes  self-managed  Fargate profiles
       │             │             │
    EC2 pods       EC2 pods    eligible pods
                 │
    VPC CNI addresses, CoreDNS and supported add-ons
```

The control plane does not provision all the application prerequisites. Managed node groups handle node provisioning and some lifecycle integration; your team still owns Kubernetes version coordination, workload disruption budgets, capacity strategy, add-on versions, data volumes and application recovery. Self-managed nodes add AMI, bootstrap and replacement work. Fargate avoids node administration but restricts workload features and resource shapes. Review the current Auto Mode contract separately before assuming it has the same ownership boundaries as the other three.

IRSA, VPC CNI and Cluster Autoscaler solve different problems: IRSA or Pod Identity gives a pod AWS credentials, VPC CNI allocates pod networking, and a node autoscaler adds capacity when pods cannot be scheduled. A Deployment replica count alone does not scale a node group. Examine unschedulable pod events and free subnet IPs before increasing replica count.

## Workload path and failure investigation

For a public web workload, trace `DNS → load balancer → target group → pod/service → container port`. A Kubernetes Service or Ingress may cause AWS resources to be created by a controller; verify the controller, target type, IAM permissions, subnet tags and health check separately. For private access, evaluate internal load balancer placement and authorized network paths.

Use this read-only sequence against an existing sandbox cluster:

```bash
aws eks describe-cluster --name "$EKS_LAB_CLUSTER" \
  --query 'cluster.{version:version,status:status,endpoint:endpoint,access:accessConfig}'
aws eks list-nodegroups --cluster-name "$EKS_LAB_CLUSTER"
aws eks list-addons --cluster-name "$EKS_LAB_CLUSTER"
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp
```

When a pod remains Pending, inspect requests, taints, affinity, available nodes and pod IP capacity. When it is Running but unreachable, check Service selectors/endpoints, target health, SG and network policy. When a pod cannot call AWS, identify the pod's intended Pod Identity/IRSA role and authorization result instead of broadening the node role. For upgrade readiness, compare Kubernetes API compatibility, add-on support, node image and workload disruption constraints before scheduling the control-plane update.

### Deployment checkpoint

On an approved existing test cluster, deploy a small Kubernetes Deployment and ClusterIP Service through your normal GitOps/manifest workflow. Check that the Service selector matches the pod labels, each pod becomes Ready, and the Service endpoints contain the expected pod IPs. Expose it through a supported ingress/load-balancer controller only after the in-cluster path works. Record the AWS target-group type and subnets selected by the controller; do not treat a created Ingress object as proof the ALB exists or that targets are healthy.

For autoscaling, run a load that increases pod demand and confirm the HPA's metric source. Then introduce a pod whose requests exceed current node capacity; inspect scheduler events and the configured node-autoscaler or Auto Mode response. Restore the workload and observe scale-down respecting disruption constraints. A Cluster Autoscaler/Karpenter template from an older release should be compared to current API versions before use.

For observability, correlate Kubernetes events, node condition, control-plane logs where enabled, container logs and AWS networking/load-balancer metrics. In particular, a CNI IP-allocation problem can look like a generic pod scheduling problem; investigate free IPs and ENI limits alongside CPU/memory. Plan recovery for control-plane, node and add-on changes separately. The current [EKS rollback workflow](https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html) permits returning to the previous minor version within seven days of an eligible in-place upgrade; it has policy, component-compatibility and automatic-upgrade restrictions. Follow that workflow rather than assuming a template rollback reverses every cluster component.

## References

- [EKS introduction and operating models](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html).
- [EKS best practices](https://docs.aws.amazon.com/eks/latest/best-practices/introduction.html).

## Across the wiki

- [[Kubernetes/eks/README|Amazon EKS]] — managed Kubernetes (Kubernetes)
- [[Azure/compute/aks|Azure Kubernetes Service (AKS) Architecture Hub]] — managed Kubernetes (Azure)
- [[GCP/compute/gke|Google Kubernetes Engine (GKE)]] — managed Kubernetes (GCP)
- [[Kubernetes/concepts/00-hub|Kubernetes Concepts]] — managed Kubernetes (Kubernetes)
