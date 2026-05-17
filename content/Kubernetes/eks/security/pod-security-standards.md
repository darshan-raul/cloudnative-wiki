---
title: Pod Security Standards
tags: [eks, security, pss, pod-security]
date: 2026-05-17
description: Kubernetes Pod Security Standards on EKS
---

# Pod Security Standards (PSS)

## Overview

PSS provides policy-based enforcement for pod security across namespaces.

## Security Modes

| Mode | Description |
|------|-------------|
| Privileged | No restrictions |
| Baseline | Minimal restrictions |
| Restricted | Heavily restricted, best practice |

## Apply Baseline Policy

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

## Restricted Policy Requirements

### Non-privileged containers
```yaml
securityContext:
  privileged: false
  allowPrivilegeEscalation: false
```

### Read-only root filesystem
```yaml
securityContext:
  readOnlyRootFilesystem: true
```

### Non-root user
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10000
```

## Example Compliant Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx
    securityContext:
      privileged: false
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

## References

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [EKS Workshop - PSS](https://www.eksworkshop.com/docs/security/pod-security-standards/)