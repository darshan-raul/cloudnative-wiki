---
title: "Runbook: EKS Hybrid Node Disconnected or Not Joining"
description: "An on-premises EKS Hybrid Node goes NotReady, never joins, or its Pods can't be reached from the cluster. Check the WAN path, credentials, remote network configuration and CNI routing."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    hybrid-nodes,
    networking,
    incident,
  ]
date: 2026-10-20
aliases: [EKS hybrid nodes runbook, hybrid node NotReady]
---

# Runbook: EKS Hybrid Node Disconnected or Not Joining

**Applies to:** EKS Hybrid Nodes: on-premises or edge Linux machines joined with `nodeadm`, using SSM hybrid activations or IAM Roles Anywhere for credentials, and Cilium or Calico for Pod networking. The VPC CNI doesn't run on hybrid nodes.
**Typical severity:** Sev 2 for a site; the cloud part of the cluster is unaffected.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

- Hybrid nodes `NotReady` or `Unknown`, often all nodes at one site at once.
- A new machine never appears in `kubectl get nodes`.
- `kubectl logs` or `exec` to Pods on hybrid nodes times out, or webhooks running on hybrid nodes fail (`failed calling webhook ... context deadline exceeded`).

## Impact

The control plane runs in AWS. When the link to a site drops, Pods at the site **keep running**, but the cluster can't see or manage them. After the default five minutes, the control plane evicts them and tries to reschedule them elsewhere. That can start duplicates in the cloud while the originals still run at the site.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1 NODE=<hybrid node>
```

## Triage

**1. One node or a site?**

```bash
kubectl get nodes -l eks.amazonaws.com/compute-type=hybrid -o wide
kubectl describe node "$NODE" | sed -n '/Conditions:/,/Addresses:/p'
```

All nodes at one site at once points to the WAN link (VPN or Direct Connect) or the site's firewall.

**2. Does the cluster know the remote networks?**

```bash
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query 'cluster.remoteNetworkConfig'
```

The node's IP must be inside `remoteNodeNetworks`. For webhooks and `kubectl logs` and `exec` to reach Pods, their CIDR must be in `remotePodNetworks` **and** routable from the VPC.

**3. On the node:**

```bash
sudo systemctl status kubelet containerd --no-pager
sudo journalctl -u kubelet --since "-30min" --no-pager | grep -Ei 'unauthorized|x509|timeout|refused' | tail -20
curl -sk -o /dev/null -w '%{http_code}\n' "$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.endpoint --output text)/healthz"
sudo nodeadm debug -c file://nodeConfig.yaml     # validates networking and credential requirements
```

**4. Credentials:**

```bash
# SSM hybrid activations
sudo systemctl status amazon-ssm-agent --no-pager
# IAM Roles Anywhere: certificate expiry
sudo openssl x509 -noout -enddate -in <path to node certificate>
```

## Diagnosis

| Signal                                                                     | Cause                                       | Fix   |
| -------------------------------------------------------------------------- | ------------------------------------------- | ----- |
| Whole site `Unknown`; endpoint unreachable from the node                   | A. WAN link or firewall                     | Fix A |
| Kubelet `Unauthorized`; Roles Anywhere certificate expired; SSM agent down | B. Node credentials                         | Fix B |
| New node never registers; no access entry of type `HYBRID_LINUX`           | C. Node role not mapped                     | Fix C |
| Node `Ready`, but webhooks, `logs` or `exec` to its Pods time out          | D. Pod network not routable from the VPC    | Fix D |
| Node `Ready`; `NetworkReady=false`                                         | E. Cilium or Calico not running on the node | Fix E |

## Fix

### A. WAN link or firewall

Restore the VPN or Direct Connect path. The node needs TCP 443 to the cluster's ENIs in the VPC (and to the public endpoint, if used). The control plane needs TCP 10250 to the kubelet for `logs`, `exec` and metrics. When the link returns, nodes report again and Pods are reconciled.

For short, known outages at edge sites, give site workloads longer tolerations, so a WAN blip doesn't trigger eviction:

```yaml
tolerations:
  - key: node.kubernetes.io/unreachable
    operator: Exists
    effect: NoExecute
    tolerationSeconds: 3600
```

### B. Node credentials

- **IAM Roles Anywhere:** renew the node's certificate before it expires. An expired certificate means the kubelet can no longer get AWS credentials, so it can't authenticate.
- **SSM hybrid activations:** the SSM agent must be running and registered. `aws ssm describe-instance-information --filters Key=ResourceType,Values=ManagedInstance` lists hybrid instances and their ping status.

### C. Node role not mapped

The hybrid nodes role needs an access entry of type `HYBRID_LINUX`:

```bash
aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" --principal-arn <hybrid-nodes-role-arn> --type HYBRID_LINUX
```

### D. Pod network not routable

Either make the site's Pod CIDR routable from the VPC (on-premises routes advertised over BGP or static routes, plus VPC route tables pointing to the VPN or Transit Gateway), or keep webhooks and anything the control plane must call on **cloud** nodes. Use a `nodeSelector` or affinity that avoids `eks.amazonaws.com/compute-type: hybrid`.

### E. CNI not running

Check the Cilium or Calico agent DaemonSet on the node, and its IP pool configuration, which must match `remotePodNetworks`. Cloud nodes run the VPC CNI; give each CNI's DaemonSet affinity so it runs only on its own node type.

## Verify recovery

```bash
kubectl get nodes -l eks.amazonaws.com/compute-type=hybrid
kubectl logs -n <ns> <pod-on-hybrid-node> --tail=5     # proves control plane → kubelet path
```

## Escalate

Open an AWS Support case if the node reaches the endpoint, credentials are valid, and registration still fails. Attach the `nodeadm` output, kubelet logs, cluster ARN and `remoteNetworkConfig`.

## Prevent

- Monitor WAN links per site, separately from node health.
- Alert on Roles Anywhere certificate expiry 30 days ahead.
- Keep webhooks and cluster-critical controllers on cloud nodes.
- Decide per workload what should happen during a site disconnect (keep running locally, or fail over to the cloud), and set tolerations to match.

## Background

- [[Kubernetes/eks/compute/hybrid-nodes/README|EKS Hybrid Nodes]]
- [Amazon EKS Hybrid Nodes overview](https://docs.aws.amazon.com/eks/latest/userguide/hybrid-nodes-overview.html)
