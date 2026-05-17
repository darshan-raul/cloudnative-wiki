---
title: Common EKS Issues
tags: [eks, troubleshooting, common-issues]
date: 2026-05-17
description: Common EKS issues and their solutions
---

# Common EKS Issues

## Node Issues

### Node Not Ready

```bash
# Describe node for details
kubectl describe node <node-name>

# Check kubelet logs
ssh admin@<node-ip>
journalctl -u kubelet

# Common causes:
# - CNI not running
# - Memory pressure
# - Disk pressure
# - kube-proxy issues
```

### Node Stuck in NotReady

```bash
# Check System pod logs
kubectl logs -n kube-system -l k8s-app=aws-node --tail=50
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=50

# Restart CNI if needed
kubectl delete pod -n kube-system -l k8s-app=aws-node
```

## Pod Issues

### Pod Stuck in Pending

```bash
# Describe pod
kubectl describe pod <pod-name>

# Check if:
# - Resources insufficient
# - Node selector/taints not matching
# - PVC not bound
# - Pending due to CNI
```

### Pod Stuck in ImagePullBackOff

```bash
# Check image name
kubectl describe pod <pod-name> | grep -A5 Events

# Verify:
# - Image exists
# - Image tag correct
# - Registry credentials valid
# - Network connectivity to registry
```

### Pod Stuck in CrashLoopBackOff

```bash
# Check logs
kubectl logs <pod-name> --previous

# Common causes:
# - Application error
# - Missing environment variables
# - Misconfigured entrypoint
# - Health check failures
```

## Networking Issues

### Cannot Reach Service

```bash
# Check service
kubectl get svc

# Check endpoints
kubectl get endpoints <service-name>

# Check DNS
kubectl run dnsutils --image=tutum/dnsutils --restart=Never -- sleep 3600
kubectl exec -it dnsutils -- nslookup <service-name>

# Check CNI
kubectl logs -n kube-system -l k8s-app=aws-node --tail=100
```

### Intermittent Connectivity

```bash
# Check MTU issues (VPC CNI)
kubectl exec -it <pod> -- cat /etc/resolv.conf

# Check security groups
aws ec2 describe-network-interfaces \
  --filters "Name=private-ip-address,Values=<pod-ip>"
```

## IRSA Issues

### IRSA Not Working

```bash
# Verify service account annotation
kubectl get sa <sa-name> -o yaml

# Check token file exists in pod
kubectl exec -it <pod> -- ls -la /var/run/secrets/eks.amazonaws.com/

# Verify OIDC provider
aws iam list-open-id-connect-providers

# Test role assumption
aws sts assume-role-with-web-identity \
  --role-arn arn:aws:iam::123456789:role/my-role \
  --web-identity-token file:///var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

## Addon Issues

### VPC CNI Not Creating Pods

```bash
# Check ENI allocation
kubectl exec -n kube-system aws-node-xxxx -- aws ec2 describe-network-interfaces

# Check max pods for instance type
kubectl exec -n kube-system aws-node-xxxx -- cat /etc/eks/max-pods.txt

# Check prefix delegation
kubectl set env daemonset/aws-node -n kube-system AWS_VPC_K8S_CNI_PREFIX_DELEGATION=true
```

### CoreDNS Issues

```bash
# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Restart CoreDNS
kubectl rollout restart -n kube-system deployment/coredns

# Check endpoints
kubectl get endpoints kube-dns -n kube-system
```

## Quick Commands Reference

```bash
# Get cluster info
aws eks describe-cluster --name my-cluster

# Update kubeconfig
aws eks update-kubeconfig --name my-cluster

# Check node groups
aws eks list-nodegroups --cluster-name my-cluster

# Update addon
aws eks update-addon --cluster-name my-cluster --addon-name vpc-cni --addon-version latest

# Get token for cluster
aws eks get-token --cluster-name my-cluster
```

## References

- [EKS Troubleshooting Guide](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [EKS Workshop - Troubleshooting](https://www.eksworkshop.com/docs/troubleshooting/)