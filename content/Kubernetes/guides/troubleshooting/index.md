---
title: Kubernetes Troubleshooting Playbooks
tags: [kubernetes, guides, troubleshooting, debugging, playbooks]
date: 2026-09-06
description: Symptom-driven troubleshooting playbooks for diagnosing and repairing common Kubernetes cluster failures.
---

# Kubernetes Troubleshooting Playbooks

Systematic, symptom-first playbooks for diagnosing and recovering from production cluster failures. Each playbook follows a standard diagnostic structure: **symptom → scope → evidence → diagnosis → correction → verification → prevention**.

## Triage Flowchart

```mermaid
flowchart TD
    Issue["Workload or Cluster Outage"] --> CheckPod{"Is Pod Running?"}
    
    CheckPod -- No --> PodStatus{"Pod Status?"}
    PodStatus -- Pending --> P_Pending["[[Kubernetes/guides/troubleshooting/pod-pending|Pod Pending]]\n(Resources, Taints, Affinity, PVC)"]
    PodStatus -- ImagePullBackOff --> P_Image["[[Kubernetes/guides/troubleshooting/image-pull|ImagePullBackOff]]\n(Name, Registry Auth, Rate Limit)"]
    PodStatus -- CrashLoopBackOff --> P_Crash["[[Kubernetes/guides/troubleshooting/crashloop-backoff|CrashLoopBackOff]]\n(Exit Code, App Panic, Config Error)"]
    
    CheckPod -- Yes --> NetCheck{"Can traffic reach Pod?"}
    NetCheck -- No --> TrafficIssue{"Traffic Failure Point?"}
    TrafficIssue -- DNS --> P_DNS["[[Kubernetes/guides/troubleshooting/dns-resolution|DNS Resolution Failure]]\n(CoreDNS, search ndots, CNI)"]
    TrafficIssue -- Service --> P_Svc["[[Kubernetes/guides/troubleshooting/service-unreachable|Service Unreachable]]\n(Selectors, Endpoints, Kube-Proxy)"]
    TrafficIssue -- Ingress/Gateway --> P_Ing["[[Kubernetes/guides/troubleshooting/ingress-404|Ingress / Gateway 404/502]]\n(Routes, Target Port, TLS)"]

    CheckPod -. Storage Stuck .-> P_PVC["[[Kubernetes/guides/troubleshooting/pvc-stuck|PVC Stuck in Pending]]\n(Provisioner, AccessMode, SC)"]
    CheckPod -. Node Unhealthy .-> P_Node["[[Kubernetes/guides/troubleshooting/node-not-ready|Node NotReady]]\n(Kubelet, DiskPressure, CNI)"]
```

## Playbook Directory

| Symptom | Primary Diagnostic Commands | Playbook |
| :--- | :--- | :--- |
| **Pod stuck in Pending** | `kubectl describe pod <pod>`, events, scheduler reasons | [[Kubernetes/guides/troubleshooting/pod-pending\|Pod Pending]] |
| **CrashLoopBackOff** | `kubectl logs <pod> --previous`, exit code, OOMKilled | [[Kubernetes/guides/troubleshooting/crashloop-backoff\|CrashLoopBackOff]] |
| **ImagePullBackOff / ErrImagePull** | `kubectl describe pod <pod>`, image pull secrets, registry reachability | [[Kubernetes/guides/troubleshooting/image-pull\|ImagePullBackOff]] |
| **Service unreachable** | `kubectl get endpointslices`, labels, selector match, port mapping | [[Kubernetes/guides/troubleshooting/service-unreachable\|Service Unreachable]] |
| **DNS resolution failure** | `kubectl logs -n kube-system -l k8s-app=kube-dns`, `resolv.conf` | [[Kubernetes/guides/troubleshooting/dns-resolution\|DNS Resolution]] |
| **Ingress 404 / 502 Bad Gateway** | Ingress controller logs, Gateway HTTPRoute, service port match | [[Kubernetes/guides/troubleshooting/ingress-404\|Ingress 404 / 502]] |
| **PVC stuck in Pending** | `kubectl describe pvc <pvc>`, StorageClass provisioner, CSI driver | [[Kubernetes/guides/troubleshooting/pvc-stuck\|PVC Stuck]] |
| **Node NotReady** | `kubectl describe node <node>`, kubelet systemd logs, disk/memory pressure | [[Kubernetes/guides/troubleshooting/node-not-ready\|Node NotReady]] |
