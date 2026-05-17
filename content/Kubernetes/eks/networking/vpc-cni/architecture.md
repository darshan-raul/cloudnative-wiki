---
title: VPC CNI Architecture
tags: [eks, networking, vpc-cni, architecture]
date: 2026-05-17
description: VPC CNI internal architecture - CNI plugin, ipamd, VPC resource controller
---

# VPC CNI Architecture

## Components Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     aws-node DaemonSet                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────┐         ┌──────────────────────────┐  │
│  │   aws-cni       │         │     aws-node             │  │
│  │   (CNI Plugin)  │◄───────►│     (ipamd daemon)      │  │
│  │                  │ Unix    │                          │  │
│  │ - ADD/DEL       │ Socket  │ - ENI management        │  │
│  │ - CHECK         │         │ - IP allocation          │  │
│  │ - GET          │         │ - Warm pool maintenance  │  │
│  └──────────────────┘         └──────────────────────────┘  │
│          │                              │                   │
│          │                              │                   │
│          ▼                              ▼                   │
│  ┌──────────────────┐         ┌──────────────────────────┐  │
│  │  /opt/cni/bin/   │         │   /var/run/aws-node/     │  │
│  │  aws-cni         │         │   ipam.json              │  │
│  └──────────────────┘         └──────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
          │                              │
          │                              │
          ▼                              ▼
┌─────────────────┐            ┌─────────────────────────────┐
│   kubelet       │            │      EC2 API               │
│  (calls CNI)    │            │  (Describe, Allocate,      │
│                 │            │   Associate addresses)    │
└─────────────────┘            └─────────────────────────────┘
```

## CNI Plugin Container (`aws-cni`)

The CNI plugin handles the actual network configuration when pods are created/deleted.

### CNI Add Flow

```
┌─────────────────────────────────────────────────────────────┐
│                        CNI ADD Command                       │
├─────────────────────────────────────────────────────────────┤
│  1. Read CNI config from /etc/cni/net.d/10-aws.conflist    │
│                                                             │
│  2. Parse container ID, netns, args from stdin             │
│                                                             │
│  3. Connect to ipamd via /var/run/aws-node/ipam.sock       │
│                                                             │
│  4. Request IP address(es) for pod                         │
│     - Pod info: namespace, name, uid                       │
│     - Returns: veth mac, IPs, gateway, DNS                 │
│                                                             │
│  5. Create veth pair in pod netns                          │
│     - Host side: eth0                                      │
│     - Pod side: eth0 (or custom via VETH_PREFIX)           │
│                                                             │
│  6. Configure host-side networking                         │
│     - Attach secondary ENI if needed                       │
│     - Setup rpfilter                                       │
│     - Add iptables rules for SNAT                          │
│                                                             │
│  7. Return success to kubelet                              │
└─────────────────────────────────────────────────────────────┘
```

### CNI Del Flow

```
┌─────────────────────────────────────────────────────────────┐
│                       CNI DEL Command                       │
├─────────────────────────────────────────────────────────────┤
│  1. Parse container ID, netns from stdin                   │
│                                                             │
│  2. Lookup pod in ipamd state (/var/run/aws-node/ipam.json)│
│                                                             │
│  3. Free IP addresses back to pool                         │
│     - Does NOT return IPs to EC2 (they stay warm)          │
│                                                             │
│  4. Remove veth pair from host                             │
│                                                             │
│  5. Update iptables rules if needed                        │
└─────────────────────────────────────────────────────────────┘
```

## ipamd Daemon (`aws-node`)

The IP Address Management Daemon (ipamd) maintains the warm pool and handles EC2 API calls.

### ipamd State File

As of v1.12.0, ipamd persists state to `/var/run/aws-node/ipam.json`:

```json
{
  "cniVersion": "0.4.0",
  "name": "aws-cni",
  "prevResult": {...},
  "ipams": [
    {
      "addr": "10.0.1.100/32",
      "deviceNumber": 5,
      "interface": "eth0"
    }
  ],
  "eni2ips": {
    "eni-abc123": ["10.0.1.50/32", "10.0.1.51/32", "10.0.1.52/32"]
  },
  "trunkENI": "eni-trunk-abc123",
  "branchENI": {}
}
```

### ipamd Initialization

On startup, ipamd:
1. Reads existing ENIs from EC2 metadata
2. Reconciles with local state file
3. Calculates warm pool needs based on `WARM_*_TARGET` settings
4. Pre-allocates ENIs/IPs to meet warm pool requirements
5. Starts background reconciliation loop

### Background Reconciliation

ipamd runs continuous reconciliation:
- Every 60 seconds: Checks if warm pool needs replenishment
- Every 60 seconds: Cleans up leaked ENIs (if any)
- Every 5 minutes: Full EC2 state sync

## VPC Resource Controller

Running on EKS control plane (not on nodes), this controller manages:
- **Trunk ENI attachment** - Attaches trunk ENIs to instances for SGP
- **Branch ENI provisioning** - Creates branch ENIs for pods with security groups
- **Extended resources** - Advertises `vpc.amazonaws.com/pod-enis` capacity

## Network Packet Flow

### Outbound (Pod → External)

```
Pod eth0 → veth host side → eth0 (node)
                                 │
                    ┌────────────┴────────────┐
                    │                         │
               SNAT via                 Direct route
               eth0 primary              (if externalSNAT=true)
                    │                         │
                    ▼                         ▼
               Internet GW               NAT Gateway
               or                          or
            NAT Gateway                External endpoint
```

### Inbound (External → Pod)

```
External → NLB/ALB → Branch ENI IP → Pod
                         or
                    Primary/Secondary ENI IP → Pod
```

## iptables Rules Created by VPC CNI

VPC CNI creates the following iptables rules on each node:

### NAT Table (SNAT for pod egress)

```bash
# Default SNAT rule (unless externalSNAT=true)
-A POSTROUTING -m comment --comment "aws-cnivpn" -m addrtype ! --dst-type LOCAL ! -d 10.0.0.0/8 -j SNAT --to-source <node_primary_ip>

# With externalSNAT=false (default), pod traffic to non-VPC destinations is SNATed
# With externalSNAT=true, pod gets its pod IP as source (no SNAT)
```

### Filter Table

```bash
# Allow traffic from trunk ENI
-A FORWARD -i eni+ -j ACCEPT

# Allow established connections
-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

## Security Groups with VPC CNI

When using Security Groups for Pods:

```
┌────────────────────────────────────────────────────────────┐
│                   Security Groups Flow                     │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  Pod with SGP:                                             │
│    - Gets branch ENI (dedicated network interface)        │
│    - Primary IP of branch ENI = pod IP                    │
│    - Security groups applied at EC2 level                  │
│                                                            │
│  Pod without SGP:                                          │
│    - Shares node's primary ENI secondary IPs              │
│    - Uses node's security groups                           │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Memory and CPU Usage

| Component | Memory (Typical) | CPU |
|-----------|-----------------|-----|
| aws-cni (CNI plugin) | ~20MB | Burst during pod creation |
| aws-node (ipamd) | ~100MB | Low (background) |

## References

- [CNI Proposal Document](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/cni-proposal.md)
- [VPC Resource Controller](https://github.com/aws/amazon-vpc-resource-controller-k8s)
- [Network Policy Agent](https://github.com/aws/aws-network-policy-agent)