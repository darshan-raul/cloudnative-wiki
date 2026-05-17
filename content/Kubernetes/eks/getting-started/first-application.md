---
title: Deploying Your First Application
tags: [eks, getting-started, deployment]
date: 2026-05-17
description: Deploying and exposing your first workload on EKS
---

# Deploying Your First Application

## Basic nginx Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
```

```bash
kubectl apply -f deployment.yaml
kubectl get pods -l app=nginx
```

## Exposing with Load Balancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-lb
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
```

```bash
kubectl apply -f service.yaml
kubectl get svc nginx-lb
# Note: External IP will show once AWS LB is provisioned
```

## Exposing with Ingress

Requires AWS Load Balancer Controller installed.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
```

## Verify Deployment

```bash
kubectl get all
kubectl describe deployment nginx
kubectl logs -l app=nginx
kubectl exec -it <pod-name> -- nginx -v
```

## Cleanup

```bash
kubectl delete -f deployment.yaml
kubectl delete -f service.yaml
```

## References

- [Deploy a sample application](https://www.eksworkshop.com/docs/introduction/getting-started/)
- [Exposing applications](https://www.eksworkshop.com/docs/fundamentals/exposing/)