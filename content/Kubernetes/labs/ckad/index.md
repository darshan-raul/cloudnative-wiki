---
title: CKAD Labs
tags: [kubernetes, labs, ckad, hands-on]
date: 2026-10-13
description: "Hands-on labs for the Certified Kubernetes Application Developer exam, from cluster setup through deploying, configuring, exposing and debugging an application."
---

# CKAD Labs

Thirteen labs for the [[Kubernetes/certifications/ckad|CKAD Track]]. Labs 02 to 06 are cumulative: they share one `podinfo` Deployment and each states the state it expects and leaves, so do them in order after Lab 01. Labs 07 to 13 each use their own namespace and stand on their own.

Lab CKAD-01 also builds the `kind` cluster that the [[Kubernetes/labs/cka/index|CKA Labs]] and [[Kubernetes/labs/cks/index|CKS Labs]] start from.

| Lab                                                                         | Title                                     | Core Focus                                                                                                       | Controlled Failure Scenario                                                       |
| :-------------------------------------------------------------------------- | :---------------------------------------- | :--------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------- |
| [[Kubernetes/labs/ckad/01-cluster-setup\|CKAD-01]]                          | **Cluster Setup & Orientation**           | Multi-node `kind` cluster, control plane and worker inspection                                                   | Node failure and recovery                                                         |
| [[Kubernetes/labs/ckad/02-deploy-workload\|CKAD-02]]                        | **Deploying the Application**             | Deployment, ReplicaSet and Pod ownership, the generated selector                                                 | A Pod ignored, adopted and released as its labels change                          |
| [[Kubernetes/labs/ckad/03-updates-and-rollbacks\|CKAD-03]]                  | **Updates & Rollbacks**                   | `maxSurge` and `maxUnavailable`, rollout history, `rollout undo`                                                 | Bad image tag causing `ImagePullBackOff`                                          |
| [[Kubernetes/labs/ckad/04-configuration\|CKAD-04]]                          | **Workload Configuration & Secrets**      | ConfigMaps and Secrets as environment variables and mounted files, what `kubectl apply` does and does not remove | Stale values surviving an apply; missing key causing `CreateContainerConfigError` |
| [[Kubernetes/labs/ckad/05-services-and-dns\|CKAD-05]]                       | **Services & DNS**                        | ClusterIP, EndpointSlices, DNS search path, NodePort                                                             | Selector typo, wrong `targetPort`, unready Pod                                    |
| [[Kubernetes/labs/ckad/06-observability-and-troubleshooting\|CKAD-06]]      | **Observability & Troubleshooting**       | metrics-server, logs, `kubectl debug`, exit codes                                                                | One-off exit, crash loop and OOM kill                                             |
| [[Kubernetes/labs/ckad/07-kustomize-and-lifecycle\|CKAD-07]]                | **Kustomize, Drift & API Deprecations**   | Base and overlays, server-side apply ownership, migrating a removed API version                                  | Apply refused by a field ownership conflict                                       |
| [[Kubernetes/labs/ckad/08-build-and-ship-images\|CKAD-08]]                  | **Build & Ship Container Images**         | Build, tag, modify, `save` and `load`, running a local image                                                     | `latest` tag forcing a registry pull                                              |
| [[Kubernetes/labs/ckad/09-ingress\|CKAD-09]]                                | **Ingress**                               | IngressClass, host and path rules, TLS from a Secret                                                             | Wrong class, wrong port, no endpoints                                             |
| [[Kubernetes/labs/ckad/10-jobs-cronjobs-and-multi-container-pods\|CKAD-10]] | **Jobs, CronJobs & Multi-Container Pods** | Completions and parallelism, schedules, init containers, sidecars, shared volumes                                | Job past its backoff limit; init container that never finishes                    |
| [[Kubernetes/labs/ckad/11-helm-release-lifecycle\|CKAD-11]]                 | **Helm Release Lifecycle**                | Values, install, upgrade, history, rollback, uninstall                                                           | Upgrade that does not come up                                                     |
| [[Kubernetes/labs/ckad/12-blue-green-and-canary\|CKAD-12]]                  | **Blue/Green & Canary Deployments**       | Two Deployments and one Service, selectors and replica ratios                                                    | Selector that catches an unrelated Pod                                            |
| [[Kubernetes/labs/ckad/13-quotas-limit-ranges-and-probes\|CKAD-13]]         | **Quotas, LimitRanges & Probes**          | ResourceQuota, LimitRange defaults and bounds, startup, readiness and liveness probes                            | Three admission rejections; slow start killed by a liveness probe                 |

DaemonSets and StatefulSets have no lab yet; see the track's gap table. Test yourself with the [[Kubernetes/certifications/ckad-mock-exam|CKAD practice set]].
