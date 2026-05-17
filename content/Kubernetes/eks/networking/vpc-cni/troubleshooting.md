---
title: VPC CNI Troubleshooting
tags: [eks, networking, vpc-cni, troubleshooting]
date: 2026-05-17
description: Debugging VPC CNI issues - pod networking problems, IP allocation, ENI issues
---

# VPC CNI Troubleshooting

## Diagnostic Commands

### Quick Health Check

```bash
# Check aws-node pods are running
kubectl get pods -n kube-system -l k8s-app=aws-node

# Check node has trunk ENI (if using SGP)
kubectl get node <node-name> -o jsonpath='{.metadata.labels.vpc\.amazonaws\.com/has-trunk-attached}'

# Check pod count vs capacity
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODS:.status.capacity.pods,MAX_PODS:.status.allocatable.pods

# View CNI logs
kubectl logs -n kube-system -l k8s-app=aws-node --tail=100
```

### ENI and IP Diagnostics

```bash
# List all ENIs attached to instance
kubectl exec -n kube-system aws-node-xxxx -- \
  aws ec2 describe-network-interfaces \
  --filters "Name=attachment.instance-id,Values=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

# List ENIs with IPs
kubectl exec -n kube-system aws-node-xxxx -- \
  aws ec2 describe-network-interfaces \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,PrivateIpAddress,Status,InterfaceType,{ENI:TagSet[?Key==`Name`].Value|[0]}]'

# Check ipamd state
kubectl exec -n kube-system aws-node-xxxx -- \
  cat /var/run/aws-node/ipam.json | jq .

# View ipamd introspection stats
kubectl exec -n kube-system aws-node-xxxx -- \
  wget -O- 127.0.0.1:61679/stats 2>/dev/null | jq .
```

## Common Issues

### Issue: Pod stuck in Pending with "Failed to allocate IP"

**Symptoms**:
```
Warning  FailedScheduling  2m (x3 over 5m)  default-scheduler  0/3 nodes are available: 1 Insufficient pods.
```

**Diagnosis**:
```bash
# Check if node has reached pod limit
kubectl get nodes <node-name> -o jsonpath='{.status.capacity.pods}' && \
kubectl get nodes <node-name> -o jsonpath='{.status.allocatable.pods}'

# Check ipamd logs for allocation failures
kubectl logs -n kube-system aws-node-xxxx -c aws-node --tail=200 | grep -i "allocate\|fail\|error"

# Check EC2 ENI attachment count
kubectl exec -n kube-system aws-node-xxxx -- \
  aws ec2 describe-network-interfaces \
  --query 'length(NetworkInterfaces)'
```

**Causes and Solutions**:

| Cause | Solution |
|-------|----------|
| Node at max pod capacity | Increase `MAX_PODS` or use larger instance type |
| Subnet IP exhaustion | Use custom networking to expand IP pool |
| ENI attachment limit reached | Use prefix delegation to increase pod density |
| EC2 API throttling | Increase WARM_IP_TARGET, reduce pod churn |

**Fix - Check max pods formula**:
```bash
# Calculate max pods for instance type
# Formula: (ENIs × (IPs_per_ENI - 1)) + 2
# For m5.xlarge: (4 × (15 - 1)) + 2 = 58
```

### Issue: Pods have no network connectivity

**Symptoms**: Pod starts but cannot reach internet or other services.

**Diagnosis**:
```bash
# Check pod can get external IP
kubectl exec -it <pod-name> -- curl -s ifconfig.me

# Check pod DNS resolution
kubectl exec -it <pod-name> -- nslookup kubernetes.default

# Check veth configuration
ip addr show

# Check routing table
ip route show

# Check iptables rules
iptables -t nat -L -n | head -20
```

**Common Causes**:

| Cause | Check | Fix |
|-------|-------|-----|
| SNAT not configured | `iptables -t nat -L POSTROUTING` | Set `externalSNAT=false` |
| Security group blocking | Check SG rules | Add rules for pod traffic |
| Route missing | `ip route` | Ensure subnet has route |
| VPC endpoints not accessible | From node | Check privateLink endpoints |

**Verify SNAT Configuration**:
```bash
# Check if SNAT is working
kubectl exec -it <pod-name> -- wget -O- ifconfig.me

# Check NAT rules on node
iptables -t nat -L POSTROUTING -v | grep -i cnivpn
```

### Issue: Cannot reach pods from external sources (Load Balancer)

**Symptoms**: ALB/NLB target shows unhealthy, or connections timeout.

**Diagnosis**:
```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# Check pod security groups
kubectl get pods -o jsonpath='{.items[*].spec.securityContext}' 

# Check if using Local external traffic policy
kubectl get svc <svc-name> -o jsonpath='{.spec.externalTrafficPolicy}'
```

**Common Causes**:

| Cause | Solution |
|-------|----------|
| Security group on pods blocking health checks | Add inbound rule for health checks |
| externalTrafficPolicy=Cluster | Change to Local if preserving source IP needed |
| NodePort not working with SGP | Use NLB with IP targets |
| Health check port mismatch | Verify containerPort matches |

**Fix - Security Group for Pods Health Check**:
```yaml
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: allow-lb-healthcheck
spec:
  podSelector:
    matchLabels:
      app: my-app
  securityGroups:
    groupIds:
      - sg-xxxxxxxx
      - sg-lb-healthcheck  # Allow 80/tcp from VPC CIDR
```

### Issue: High pod startup latency

**Symptoms**: Pods take 30+ seconds to get IP and become ready.

**Diagnosis**:
```bash
# Time pod creation
time kubectl apply -f test-pod.yaml

# Check ipamd startup logs
kubectl logs -n kube-system aws-node-xxxx -c aws-node --tail=50 | grep -i init

# Check WARM target settings
kubectl exec -n kube-system aws-node-xxxx -- \
  env | grep -i warm
```

**Solutions**:

| Cause | Fix |
|-------|-----|
| Low WARM_IP_TARGET | Increase to 5-10 |
| No MINIMUM_IP_TARGET | Set to expected pod density |
| EC2 API throttling | Review and increase targets |
| Node in different AZ than ENIConfig | Ensure AZ match |

**Recommended Settings for Fast Pod Launch**:
```yaml
env:
- name: AWS_VPC_K8S_CNI_MINIMUM_IP_TARGET
  value: "30"
- name: AWS_VPC_K8S_CNI_WARM_IP_TARGET
  value: "5"
```

### Issue: IP addresses exhausted in subnet

**Symptoms**: Cannot create new ENIs or assign IPs to pods.

**Diagnosis**:
```bash
# Check available IPs in subnet
aws ec2 describe-subnets \
  --subnet-ids subnet-xxxxxxxx \
  --query 'Subnets[0].[SubnetId,AvailableIpAddressCount,CidrBlock]'

# Check all ENIs in subnet
aws ec2 describe-network-interfaces \
  --filters "Name=subnet-id,Values=subnet-xxxxxxxx" \
  --query 'length(NetworkInterfaces)'
```

**Solutions**:
1. Use custom networking to use different subnet
2. Expand VPC CIDR
3. Use prefix delegation to maximize IPs per ENI
4. Use IPv6 to increase address space

### Issue: Security Groups for Pods not working

**Symptoms**: Pods not getting branch ENI, SGP not applying.

**Diagnosis**:
```bash
# Check if ENABLE_POD_ENI is set
kubectl exec -n kube-system aws-node-xxxx -- \
  env | grep ENABLE_POD_ENI

# Check if node has trunk attached
kubectl get node <node-name> -o jsonpath='{.metadata.labels.vpc\.amazonaws\.com/has-trunk-attached}'

# Check branch ENI capacity
kubectl get node <node-name> -o jsonpath='{.status.capacity.vpc\.amazonaws\.com/pod-enis}'

# Check SecurityGroupPolicy exists
kubectl get securitygrouppolicies -A
```

**Common Issues**:

| Issue | Check | Fix |
|-------|-------|-----|
| Node not Nitro | Instance type | Use Nitro instance |
| VPC CNI too old | Version | Upgrade to v1.7.0+ |
| SGP CRD not created | `kubectl get crd securitygrouppolicies.vpcresources.k8s.aws` | Install vpc-cni with SGP support |
| Rate limiting | Controller logs | Reduce pod churn rate |

**Verify SGP Configuration**:
```bash
# Get pod's security groups
kubectl get pod <pod-name> -o jsonpath='{.metadata.annotations.vpc\.amazonaws\.com/securityGroups}'

# Get pod's branch ENI
kubectl exec -n kube-system aws-node-xxxx -- \
  aws ec2 describe-network-interfaces \
  --query 'NetworkInterfaces[?InterfaceType==`branch`].[NetworkInterfaceId,PrivateIpAddress]'
```

### Issue: EC2 API Throttling

**Symptoms**: Log entries showing "ThrottlingException", slow pod allocation.

**Diagnosis**:
```bash
# Check for throttle errors in logs
kubectl logs -n kube-system aws-node-xxxx -c aws-node --tail=500 | grep -i throttle

# Count API calls
kubectl exec -n kube-system aws-node-xxxx -- \
  aws ec2 describe-network-interfaces --filters Name=attachment.instance-id,Values=$(curl -s 169.254.169.254/latest/meta-data/instance-id) 2>&1 | head
```

**Solutions**:

| Setting | Current | Recommended |
|---------|---------|-------------|
| WARM_IP_TARGET | 1 | 5-10 |
| MINIMUM_IP_TARGET | unset | Pod density per node |
| WARM_ENI_TARGET | 1 | 1 (keep at 1) |

**Best Practice for Throttling**:
```bash
# Use MINIMUM_IP_TARGET to pre-allocate (reduces API calls)
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_MINIMUM_IP_TARGET=30 \
  AWS_VPC_K8S_CNI_WARM_IP_TARGET=3
```

## Network Policy Debugging

### Verify Calico/Network Policy is Working

```bash
# Check if Calico is running
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check for policy controller
kubectl get pods -n kube-system -l k8s-app=calico-policy-controller

# Test policy enforcement
kubectl exec -it <pod-with-policy> -- wget -O- --timeout=2 http://<blocked-pod-ip> 2>&1 | head
```

### Common Network Policy Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| Default deny not applied | All traffic allowed | Add default deny policy |
| DNS blocked | Pod can't resolve names | Add DNS egress rule |
| Policy not matching pods | Traffic still allowed | Check podSelector labels |

## Log Analysis

### CNI Plugin Logs

```bash
# Real-time CNI logs
kubectl logs -n kube-system -l k8s-app=aws-node -c aws-cni --follow --tail=100

# Search for specific pod
kubectl logs -n kube-system -l k8s-app=aws-node -c aws-cni | grep <pod-name>
```

### ipamd Logs

```bash
# ipamd daemon logs
kubectl logs -n kube-system -l k8s-app=aws-node -c aws-node --follow --tail=100

# Search for ENI/IP operations
kubectl logs -n kube-system -l k8s-app=aws-node -c aws-node | grep -E "ENI|allocate|free"
```

### aws-cni-support.sh Script

AWS provides a diagnostic script:

```bash
# Run on node via nsenter
kubectl debug node/<node-name> -it --image=amazon/aws-eks-node-agent:latest -- /aws-cni-support.sh
```

Output includes:
- ENI and IP configuration
- iptables rules
- Network namespace configuration
- VPC CNI state

## Health Check Matrix

| Check | Command | Expected |
|-------|---------|----------|
| aws-node pod running | `kubectl get po -n kube-system -l k8s-app=aws-node` | All pods Running |
| ENIs attached | `aws ec2 describe-nics` | Expected count |
| IPAM state | `cat /var/run/aws-node/ipam.json` | Valid JSON |
| Trunk attached (SGP) | Node label `vpc.amazonaws.com/has-trunk-attached=true` | true |
| Branch ENIs | `describe-nics --filter InterfaceType=branch` | Per-pod count |
| No leaked ENIs | `describe-nics` | No ENIs without active attachment |

## References

- [VPC CNI Troubleshooting Guide](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/troubleshooting.md)
- [EKS Troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [EKS Best Practices - Networking](https://aws.github.io/aws-eks-best-practices/networking/)