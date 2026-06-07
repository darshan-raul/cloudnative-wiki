---
title: "L01 — Architecture"
tags: [kubernetes, k8s, architecture, control-plane, nodes]
date: 2026-06-06
description: Kubernetes cluster architecture — control plane, nodes, namespaces, HA topology
---

# L01 — Architecture

What runs inside a Kubernetes cluster, and where. Once this is clear, every other level is "now do something with those components".

## What you'll understand after this level

- The difference between **control plane** and **worker nodes**
- What every component in the control plane does (`kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`, `cloud-controller-manager`)
- What runs on every node (`kubelet`, `kube-proxy`, container runtime)
- How a request flows from `kubectl apply` to a running pod
- How multi-master HA topology works
- What a namespace is and how it differs from a regular cluster

## Notes in this level

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L01-architecture/01-setting-up-cluster\|Setting up a Cluster]] | 🟡 | Ways to run a local/dev cluster (k3s, kind, minikube), and a real-cluster primer (kubeadm, the-hard-way) |
| [[Kubernetes/concepts/L01-architecture/02-high-availability\|High Availability]] | ✅ | etcd quorum, multi-master, control-plane failure modes |
| [[Kubernetes/concepts/L01-architecture/03-namespaces\|Namespaces]] | ✅ | What namespaces are, default limits, when to use them |
| [[Kubernetes/concepts/L01-architecture/04-local-deployment\|Local Deployment]] | ⚪ | Running k8s locally for dev (k3d, kind, minikube comparison) |
| [[Kubernetes/concepts/L01-architecture/05-need-for-swapoff\|Need for swapoff]] | ⚪ | Why kubelet refuses to run on a node with swap enabled |
| [[Kubernetes/concepts/L01-architecture/06-what-happens-when\|What Happens When…]] | ⚪ | End-to-end trace of a `kubectl apply` through every component |

## Suggested reading order

1. [[Kubernetes/concepts/L01-architecture/01-setting-up-cluster|Setting up a Cluster]] — get a cluster running
2. [[Kubernetes/concepts/L01-architecture/03-namespaces|Namespaces]] — the first thing to know to organize anything
3. [[Kubernetes/concepts/L01-architecture/02-high-availability|High Availability]] — what "production" means in k8s
4. [[Kubernetes/concepts/L01-architecture/06-what-happens-when|What Happens When…]] — tie it all together with a request trace
5. The other two are reference notes — read when you hit the topic in practice

## Where to go next

→ [[Kubernetes/concepts/L02-objects|L02 — Objects]]: now that you know the components, learn the data model they manipulate.
