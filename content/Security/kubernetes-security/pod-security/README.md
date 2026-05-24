---
title: Pod Security
tags: [kubernetes, security, pod-security, pss, psa, psp]
date: 2025-05-24
description: Kubernetes Pod Security - PodSecurityStandards (PSS), Security Context, and pod hardening for EKS workloads
---

# Pod Security 🔒

Pod security controls what a pod can and cannot do at the kernel level.

## PodSecurityStandards (PSS)

Three built-in policies (replacing the deprecated PodSecurityPolicies):

| Policy | Description |
|--------|-------------|
| `privileged` | Unrestricted — for system-level workloads |
| `baseline` | Minimal restrictions — default for most |
| `restricted` | Hardened — follow security best practices |

## Enforce PSS at Namespace Level

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

## Security Context

Configure at pod or container level:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: my-app:latest
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsUser: 1000
      capabilities:
        drop:
        - ALL
```

## Key Settings

| Setting | Secure Value | Why |
|---------|-------------|-----|
| `runAsNonRoot` | `true` | Containers don't run as root |
| `allowPrivilegeEscalation` | `false` | Can't gain more privileges |
| `readOnlyRootFilesystem` | `true` | No writable filesystem |
| `capabilities.drop` | `ALL` | Drop all Linux capabilities |
| `seccompProfile.type` | `RuntimeDefault` | Use default seccomp profile |

## RunAsUser / FSGroup

```yaml
securityContext:
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
```

## Related

- [[Security/kubernetes-security/README|K8s Security Hub]]
- [[Security/devsecops/container-security/README|Container Security]]