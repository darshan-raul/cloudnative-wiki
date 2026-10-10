---
title: Common EKS Issues
tags: [eks, troubleshooting, operations]
date: 2026-05-17
description: A symptom-indexed catalogue of the problems specific to EKS — access, node joins, pod IP exhaustion, image pulls from ECR, load balancers, storage, DNS, pod IAM and upgrades — each with cause, confirmation and fix.
---

# Common EKS Issues

These are the failures that come from the AWS integration rather than from Kubernetes itself. For the method, see [[Kubernetes/eks/troubleshooting/README|EKS troubleshooting]]; for generic Kubernetes symptoms, the [[Kubernetes/guides/troubleshooting/index|troubleshooting playbooks]].

## Access to the cluster

| Symptom                                                     | Cause                                                                                        | Fix                                                                                                                                              |
| :---------------------------------------------------------- | :------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------- |
| `error: You must be logged in to the server (Unauthorized)` | The IAM principal is not known to the cluster                                                | Add an [[Kubernetes/eks/security/access/cluster-access-management\|access entry]]; check `aws sts get-caller-identity` shows the role you expect |
| `Forbidden: User "…" cannot list resource …`                | Authenticated, but no permission                                                             | Associate an access policy or bind the entry's group with [[Kubernetes/concepts/L07-security/01-api-access/03-rbac\|RBAC]]                       |
| `dial tcp … i/o timeout`                                    | Private API endpoint and you are outside the VPC, or your IP is not in the public allow-list | [[Kubernetes/eks/security/access/endpoint-access\|Endpoint access]]                                                                              |
| Worked yesterday, `Unauthorized` today                      | Expired SSO session, or the kubeconfig references a profile that no longer exists            | `aws sso login`, then `aws eks update-kubeconfig` again                                                                                          |

## Nodes do not join or go NotReady

Confirm with `aws eks describe-nodegroup … --query nodegroup.health` and, on the instance, `journalctl -u kubelet`.

| Symptom                                             | Cause                                                                                            | Fix                                                                                                                          |
| :-------------------------------------------------- | :----------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------- |
| Instance runs, never appears in `kubectl get nodes` | Node role has no access entry (self-managed, Karpenter) or lacks the worker policies             | Create an `EC2_LINUX` access entry; attach the three managed node policies                                                   |
| Same, in a private subnet                           | No route to the API endpoint or to ECR/S3/STS                                                    | NAT gateway, or VPC endpoints — [[Kubernetes/eks/advanced/advanced-networking\|private clusters]]                            |
| Same, after switching to AL2023                     | Old `bootstrap.sh` user data; AL2023 needs a `NodeConfig`                                        | Rewrite user data — [[Kubernetes/eks/compute/managed-node-groups/basics\|node group basics]]                                 |
| Node `NotReady`, `cni plugin not initialized`       | `aws-node` pod not running on that node                                                          | Check the DaemonSet, its IAM permissions and tolerations                                                                     |
| Node `NotReady` under load                          | kubelet starved: no system reservations, disk pressure, or PID exhaustion                        | Set `kubeReserved`/`systemReserved`; larger root volume; [[Kubernetes/guides/troubleshooting/node-not-ready\|Node NotReady]] |
| Nodes vanish and are replaced repeatedly            | Spot reclaim, Karpenter drift from an unpinned AMI, or node auto repair reacting to a real fault | [[Kubernetes/eks/compute/karpenter/README\|Karpenter]], [[Kubernetes/eks/compute/managed-node-groups/spot\|Spot]]            |

## Pods stuck Pending or ContainerCreating

| Event text                                           | Cause                                                                              | Fix                                                                                                                                                                                        |
| :--------------------------------------------------- | :--------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `failed to assign an IP address to container`        | Subnet has no free IPs, or the node hit its ENI/IP limit                           | [[Kubernetes/eks/networking/vpc-cni/prefix-delegation\|Prefix delegation]], more subnets via [[Kubernetes/eks/networking/vpc-cni/custom-networking\|custom networking]], tune warm targets |
| `Too many pods`                                      | The node's `maxPods` is reached (derived from ENI limits)                          | Larger instance type or prefix delegation with a recalculated `maxPods`                                                                                                                    |
| `0/N nodes are available: … Insufficient cpu`        | No capacity and nothing is adding nodes                                            | Check the autoscaler's logs; account vCPU quota; NodePool limits                                                                                                                           |
| `volume node affinity conflict`                      | The pod's [[Kubernetes/eks/storage/ebs-csi\|EBS volume]] is in a zone with no room | Capacity in that zone; one node group per zone                                                                                                                                             |
| `had untolerated taint`                              | Tainted node group without a matching toleration                                   | Add the toleration, or a node group without the taint                                                                                                                                      |
| `FailedCreatePodSandBox … context deadline exceeded` | CNI slow or failing, often EC2 API throttling during a scale-up burst              | Warm IP targets, prefix delegation; check `ipamd.log`                                                                                                                                      |

More: [[Kubernetes/guides/troubleshooting/pod-pending|Pod Pending]] and [[Kubernetes/eks/networking/vpc-cni/troubleshooting|VPC CNI troubleshooting]].

## Image pulls

| Symptom                                                          | Cause                                                                                                     | Fix                                                                                                        |
| :--------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------- |
| `ImagePullBackOff`, `no basic auth credentials` / `403` from ECR | Node role lacks ECR pull permissions, or the repository is in another account without a repository policy | Attach `AmazonEC2ContainerRegistryPullOnly`; add a cross-account repository policy                         |
| Timeout pulling from ECR in a private subnet                     | Missing `ecr.api`, `ecr.dkr` or the S3 **gateway** endpoint                                               | Add all three; layers are served from S3                                                                   |
| `toomanyrequests` from Docker Hub                                | Anonymous pull rate limit, shared by every node behind one NAT IP                                         | ECR pull-through cache, or mirror the images                                                               |
| `exec format error` at start                                     | x86 image on a [[Kubernetes/eks/compute/managed-node-groups/graviton\|Graviton]] node, or the reverse     | Build multi-arch images; add a `kubernetes.io/arch` node selector                                          |
| Very slow pulls, pods take minutes to start                      | Multi-gigabyte images                                                                                     | Smaller images — [[Containers/images-and-layers\|images and layers]]; pre-pull or use a faster root volume |

## Load balancers and ingress

| Symptom                                 | Cause                                                                                                                                                | Fix                                                                       |
| :-------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| Ingress has no `ADDRESS`                | AWS Load Balancer Controller not installed, no `IngressClass`, or controller lacks IAM                                                               | `kubectl describe ingress`; controller logs                               |
| `couldn't auto-discover subnets`        | Subnets not tagged `kubernetes.io/role/elb` or `internal-elb`                                                                                        | Tag the subnets                                                           |
| Targets `unhealthy`                     | Wrong health-check path or port; a [[Kubernetes/eks/networking/vpc-cni/network-policies\|network policy]] or security group blocks the load balancer | Fix the annotation; allow the load balancer's source                      |
| 502/504 during deployments              | Pods are killed while still registered as targets                                                                                                    | `preStop` sleep longer than the deregistration delay; pod readiness gates |
| A Classic Load Balancer appeared        | Plain `type: LoadBalancer` handled by the legacy in-tree controller                                                                                  | Set `loadBalancerClass: service.k8s.aws/nlb`                              |
| VPC cannot be deleted after the cluster | Load balancers and ENIs were orphaned because the cluster was deleted first                                                                          | Delete Services and Ingresses before the cluster                          |

## Storage

| Symptom                                | Cause                                                       | Fix                                                          |
| :------------------------------------- | :---------------------------------------------------------- | :----------------------------------------------------------- |
| PVC `Pending`, no events               | No default StorageClass, or the CSI driver is not installed | Install the add-on; create a default class                   |
| PVC `Pending`, `UnauthorizedOperation` | CSI controller has no IAM role or lacks KMS permissions     | Fix the Pod Identity association and key policy              |
| `Multi-Attach error`                   | Volume still attached to a dead node                        | Wait for force-detach or delete the stale `VolumeAttachment` |
| EFS mount times out                    | No mount target in the zone, or port 2049 closed            | [[Kubernetes/eks/storage/efs-csi\|EFS CSI]]                  |

## DNS

| Symptom                                       | Cause                                                             | Fix                                                                                      |
| :-------------------------------------------- | :---------------------------------------------------------------- | :--------------------------------------------------------------------------------------- |
| Intermittent 5-second lookups or `SERVFAIL`   | CoreDNS overloaded, or all replicas on one node                   | Scale CoreDNS (the add-on supports autoscaling), spread replicas, add NodeLocal DNSCache |
| Intermittent failures under high query volume | The per-ENI limit of 1,024 packets per second to the VPC resolver | Spread CoreDNS across nodes; cache; check the `linklocal_allowance_exceeded` ENA metric  |
| External names slow, many `NXDOMAIN` in logs  | `ndots:5` makes each lookup try several search suffixes first     | Use fully qualified names with a trailing dot, or lower `ndots` in `dnsConfig`           |
| CoreDNS `Pending` on a Fargate-only cluster   | No Fargate profile matches it                                     | [[Kubernetes/eks/compute/fargate/README\|Fargate]]                                       |

Details: [[Kubernetes/guides/troubleshooting/dns-resolution|DNS resolution]] and [[Linux/networking/dns-resolution|Linux DNS resolution]].

## Pod IAM

| Symptom                                                                       | Cause                                                                   | Fix                                                                                                        |
| :---------------------------------------------------------------------------- | :---------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------- |
| `AccessDenied`, and the error names the **node** role                         | The pod is not using its own role                                       | Check `serviceAccountName`; check the association or the IRSA annotation                                   |
| IRSA: `InvalidIdentityToken` or `AccessDenied` on `AssumeRoleWithWebIdentity` | Trust policy has the wrong OIDC provider, namespace or service account  | Fix the `sub` condition — [[Kubernetes/eks/security/iam-roles-for-sa\|IRSA]]                               |
| Pod Identity: SDK cannot find credentials                                     | Agent add-on missing, pod created before the association, or an old SDK | Install `eks-pod-identity-agent`; restart the pod — [[Kubernetes/eks/security/pod-identity\|Pod Identity]] |
| Works in one cluster, not in another                                          | IRSA trust policies are per cluster OIDC provider                       | Add the second provider, or move to Pod Identity                                                           |

## Admission webhooks

`Internal error occurred: failed calling webhook … context deadline exceeded` on every apply means the control plane cannot reach a webhook pod: a closed security group port, or the webhook pods are down. See the failure table in [[Kubernetes/eks/security/policy-management|policy management]].

## Upgrades

| Symptom                                           | Cause                                                        | Fix                                                                                                |
| :------------------------------------------------ | :----------------------------------------------------------- | :------------------------------------------------------------------------------------------------- |
| Upgrade blocked by cluster insights               | Deprecated APIs still in use, or add-on/kubelet version skew | Resolve each finding; query audit logs for the calling client                                      |
| Node group update fails with `PodEvictionFailure` | A PDB allows zero disruptions                                | Fix the [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget\|PDB]], or force       |
| Workloads break after the upgrade                 | Removed API versions in manifests or Helm charts             | [[Kubernetes/guides/non-functional/deprecations\|Deprecations]]                                    |
| Add-on `DEGRADED` after the upgrade               | Add-on version incompatible with the new Kubernetes version  | Update add-ons as part of the [[Kubernetes/eks/cluster-upgrades/upgrade-process\|upgrade process]] |

## Related

- [[Kubernetes/eks/troubleshooting/support-resources|Support resources]]
- [[Kubernetes/concepts/L08-operations/03-common-failure-modes|Common failure modes]]
- [[Linux/troubleshooting/common-issues|Common Linux issues]]
- [EKS troubleshooting guide](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
