---
title: Deploying Your First Application on EKS
tags: [eks, getting-started, deployment, load-balancer]
date: 2026-05-17
description: A first end-to-end deployment on EKS — connect kubectl, deploy a workload, expose it through an AWS load balancer, see where AWS resources appear, give the pod AWS permissions, and clean up without leaving orphans.
---

# Deploying Your First Application on EKS

This walkthrough deploys `podinfo`, the same sample workload used in the [[Kubernetes/labs/01-deploy-workload|Kubernetes labs]], and follows each step into AWS so you can see what EKS adds to plain Kubernetes. It assumes a cluster from [[Kubernetes/eks/getting-started/cluster-creation|cluster creation]].

## 1. Connect

```bash
aws eks update-kubeconfig --name my-cluster --region eu-west-1
kubectl get nodes -o wide
```

`update-kubeconfig` does not store a password. It writes an `exec` entry that runs `aws eks get-token` on every request, so `kubectl` authenticates as your current [[AWS/security/iam/README|IAM]] identity.

| Error                                                     | Meaning                                                                                                                       |
| :-------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------- |
| `You must be logged in to the server (Unauthorized)`      | Your IAM principal has no [[Kubernetes/eks/security/access/cluster-access-management\|access entry]] on this cluster          |
| `Unable to connect to the server: dial tcp … i/o timeout` | The API endpoint is private and you are outside the VPC — [[Kubernetes/eks/security/access/endpoint-access\|endpoint access]] |
| No nodes listed                                           | The cluster has no compute yet, or nodes failed to join                                                                       |

## 2. Deploy

```yaml
# podinfo.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: podinfo
  namespace: demo
spec:
  replicas: 2
  selector:
    matchLabels: { app: podinfo }
  template:
    metadata:
      labels: { app: podinfo }
    spec:
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
          ports:
            - containerPort: 9898
          resources:
            requests: { cpu: 100m, memory: 64Mi }
            limits: { memory: 128Mi }
          readinessProbe:
            httpGet: { path: /readyz, port: 9898 }
---
apiVersion: v1
kind: Service
metadata:
  name: podinfo
  namespace: demo
spec:
  selector: { app: podinfo }
  ports:
    - port: 80
      targetPort: 9898
```

```bash
kubectl create namespace demo
kubectl apply -f podinfo.yaml
kubectl get pods -n demo -o wide
```

Look at the pod IPs: they are addresses from your VPC subnets, not from an overlay network. That is the [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]] at work, and it means anything in the VPC can route to a pod directly.

Test before exposing anything:

```bash
kubectl port-forward -n demo svc/podinfo 8080:80
curl localhost:8080
```

## 3. Expose it

A `ClusterIP` Service is only reachable inside the cluster. To reach it from outside you need an AWS load balancer, created by a controller that watches Kubernetes objects.

- On [[Kubernetes/eks/compute/eks-auto-mode/README|EKS Auto Mode]], load balancing is built in.
- Otherwise install the **AWS Load Balancer Controller** first. The legacy in-tree controller still creates Classic Load Balancers for plain `type: LoadBalancer` Services; do not rely on it.

**HTTP through an Application Load Balancer:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: podinfo
  namespace: demo
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: podinfo
                port: { number: 80 }
```

```bash
kubectl apply -f ingress.yaml
kubectl get ingress -n demo -w      # ADDRESS appears after 1–3 minutes
curl http://$(kubectl get ingress podinfo -n demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

With `target-type: ip` the load balancer sends traffic straight to pod IPs, skipping the node's `kube-proxy` hop. For TCP or UDP, use a Service of `type: LoadBalancer` with `loadBalancerClass: service.k8s.aws/nlb` instead. Concepts: [[Kubernetes/concepts/L04-services-networking/02-services|Services]], [[Kubernetes/concepts/L04-services-networking/04-ingress|Ingress]] and [[Kubernetes/concepts/L04-services-networking/09-gateway-api|Gateway API]]; the AWS side is in [[AWS/networking/load-balancing/README|Elastic Load Balancing]].

If the address never appears:

```bash
kubectl describe ingress podinfo -n demo            # events carry the reason
kubectl logs -n kube-system deploy/aws-load-balancer-controller | tail
```

The usual causes are missing subnet tags (`kubernetes.io/role/elb=1`), a controller without IAM permissions, or no `IngressClass` named `alb`.

## 4. See what was created in AWS

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].{name:LoadBalancerName,dns:DNSName,scheme:Scheme}'
aws elbv2 describe-target-groups --query 'TargetGroups[].{name:TargetGroupName,type:TargetType}'
```

One Ingress produced a load balancer, listeners, a target group with your pod IPs registered, and [[AWS/networking/vpc/security-groups|security group]] rules. Each of these costs money and each is owned by a Kubernetes object — which matters at clean-up time.

## 5. Scale it

```bash
kubectl scale deploy/podinfo -n demo --replicas=6
kubectl get pods -n demo -w
```

If pods stay `Pending`, the nodes are full. Whether more appear depends on the compute model: nothing happens with a fixed node group; [[Kubernetes/eks/compute/managed-node-groups/cluster-autoscaler|Cluster Autoscaler]], [[Kubernetes/eks/compute/karpenter/README|Karpenter]] or Auto Mode add nodes. `kubectl describe pod` tells you why a pod is not scheduled — [[Kubernetes/guides/troubleshooting/pod-pending|Pod Pending]].

## 6. Give the pod AWS permissions

Sooner or later the application calls S3 or SQS. Never put access keys in a Secret or widen the node role. Bind an IAM role to the pod's service account:

```bash
kubectl create serviceaccount podinfo -n demo

aws eks create-pod-identity-association \
  --cluster-name my-cluster \
  --namespace demo \
  --service-account podinfo \
  --role-arn arn:aws:iam::111122223333:role/podinfo-s3-read
```

Set `serviceAccountName: podinfo` in the pod spec and the AWS SDK picks up temporary credentials automatically. How it works: [[Kubernetes/eks/security/pod-identity|EKS Pod Identity]].

## 7. Clean up — in this order

```bash
kubectl delete namespace demo        # deletes the Ingress → controller deletes the ALB
# wait until the load balancer is gone, then:
eksctl delete cluster --name my-cluster
```

Delete Kubernetes objects **before** the cluster. If the cluster goes first, the controllers that own the load balancers and [[Kubernetes/eks/storage/ebs-csi|EBS volumes]] disappear, the AWS resources are orphaned and keep billing, and the leftover ENIs block deletion of the VPC.

## Where next

- Persistent data: [[Kubernetes/eks/storage/README|storage on EKS]]
- Logs and metrics: [[Kubernetes/eks/observability/README|observability]]
- Deployment automation: [[Kubernetes/eks/automation/README|GitOps and pipelines]]
- Hardening: [[Kubernetes/eks/security/README|EKS security]]
- The full learning path: [[Kubernetes/concepts/00-hub|Concepts Hub]]

## Related

- [[Kubernetes/eks/getting-started/README|Getting started with EKS]]
- [[Kubernetes/concepts/L03-workloads/03-deployments|Deployments]]
- [[Kubernetes/eks/troubleshooting/common-issues|Common EKS issues]]
- [EKS Workshop](https://www.eksworkshop.com/)
