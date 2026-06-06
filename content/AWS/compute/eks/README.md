---
title: Amazon EKS
description: Amazon EKS — managed Kubernetes on EC2 or Fargate. Clusters, node groups, Fargate profiles, add-ons, IRSA, and Kubernetes networking (CNI, CoreDNS, kube-proxy).
tags:
  - aws
  - compute
  - containers
  - kubernetes
  - eks
---

# Amazon EKS (Elastic Kubernetes Service)

EKS provides a managed Kubernetes control plane. You manage worker nodes (EC2 or Fargate), deploy applications using standard Kubernetes manifests, and AWS manages the control plane (API server, etcd, scheduler) with high availability and automatic upgrades.

## Core Concepts

### EKS Architecture

```
┌─────────────────────────────────────────────────┐
│  AWS Managed (EKS Control Plane)                 │
│                                                 │
│  API Server ── High Availability (3 AZs)        │
│  etcd ── Replicated across 3 AZs               │
│  Scheduler ── Distributes pods                  │
└─────────────────────────────────────────────────┘
              │
              │ kubeconfig (kubectl)
              ▼
┌─────────────────────────────────────────────────┐
│  Worker Nodes (your responsibility)              │
│                                                 │
│  ┌─────────────┐  ┌─────────────┐              │
│  │  Node Group │  │  Node Group  │              │
│  │  (EC2 m5.x) │  │  (EC2 m5.2x)│              │
│  └─────────────┘  └─────────────┘              │
│                                                 │
│  Or: Fargate (serverless pods)                  │
└─────────────────────────────────────────────────┘
```

### Managed Add-ons

EKS provides managed versions of core Kubernetes components:

| Add-on | Purpose | Managed by |
|--------|---------|-----------|
| kube-proxy | Pod networking | EKS |
| CoreDNS | Service discovery | EKS |
| VPC CNI | Pod networking (ENI) | EKS |
| kube-proxy | Network rules | EKS |
| AWS Load Balancer Controller | ALB/NLB ingress | You |

## Creating a Cluster

### Via Console

EKS → Clusters → Create cluster → Configure name, role, VPC, endpoint access

### Via CLI (eksctl)

```bash
# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp

# Create cluster
eksctl create cluster \
  --name my-cluster \
  --region us-east-1 \
  --version 1.29 \
  --nodegroup-name standard-workers \
  --node-type m5.xlarge \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 10 \
  --with-oidc \
  --ssh-access
```

### Via CLI (AWS)

```bash
# Create cluster
aws eks create-cluster \
  --name my-cluster \
  --role-arn arn:aws:iam::123456789012:role/eks-cluster-role \
  --resources-vpc-config '{
    "subnetIds": ["subnet-xxxxx", "subnet-yyyyy"],
    "endpointPublicAccess": true,
    "endpointPrivateAccess": true
  }' \
  --kubernetes-version 1.29

# Update kubeconfig
aws eks update-kubeconfig --name my-cluster

# Verify
kubectl get nodes
```

## Node Groups

### Managed Node Groups

```bash
# Create node group
aws eks create-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name standard-workers \
  --subnets subnet-xxxxx subnet-yyyyy \
  --instance-types m5.xlarge \
  --node-role arn:aws:iam::123456789012:role/eks-node-role \
  --scaling-config minSize=2,maxSize=10,desiredSize=3
```

### Self-Managed Nodes

Use Launch Templates for custom configurations (bottlerocket, custom AMIs):

```bash
aws eks create-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name custom-workers \
  --subnets subnet-xxxxx \
  --launch-template '{"Id": "lt-xxxxx", "Version": "1"}'
```

## Fargate

Fargate allows running pods without managing EC2 instances:

```bash
# Create Fargate profile
aws eks create-fargate-profile \
  --cluster-name my-cluster \
  --fargate-profile-name webapp-profile \
  --selectors '[{
    "namespace": "webapp",
    "labels": [{"key": "environment", "value": "production"}]
  }]' \
  --subnets subnet-xxxxx subnet-yyyyy
```

Pods matching the selector run on Fargate (serverless).

## VPC CNI (Container Network Interface)

The VPC CNI creates ENIs and attaches them to nodes. Pods get IP addresses from the VPC subnet:

```
Node (EC2)
  └── Primary ENI (eth0) → VPC subnet IP
        └── Secondary ENIs (for pods)
              └── Each secondary ENI → multiple pod IPs
```

### CNI Metrics

```bash
kubectl get pods -n kube-system -l k8s-app=aws-node
kubectl exec -n kube-system aws-node-xxxxx -- ip link show
```

## IRSA (IAM Role for Service Accounts)

Pods can assume IAM roles via ServiceAccount annotations:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: webapp
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-app-role
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  template:
    spec:
      serviceAccountName: my-app
      containers:
      - name: my-app
        image: my-app:latest
        env:
        - name: AWS_WEB_IDENTITY_TOKEN_FILE
          value: /var/run/secrets/eks.amazonaws.com/serviceaccount/token
        - name: AWS_ROLE_ARN
          value: arn:aws:iam::123456789012:role/my-app-role
```

IRSA creates and manages OIDC identity providers in your cluster.

## Deploying Applications

### Standard Kubernetes Manifest

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-webapp
  namespace: webapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-webapp
  template:
    metadata:
      labels:
        app: my-webapp
    spec:
      containers:
      - name: my-webapp
        image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-webapp:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: my-webapp
  namespace: webapp
spec:
  type: LoadBalancer
  selector:
    app: my-webapp
  ports:
  - port: 80
    targetPort: 8080
```

```bash
kubectl apply -f deployment.yaml
kubectl get pods -n webapp
kubectl get svc -n webapp
```

### AWS Load Balancer Controller

Install the AWS Load Balancer Controller for ALB ingress:

```bash
# Install via helm or eksctl
eksctl create addon --name aws-load-balancer-controller --cluster my-cluster
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-webapp
  namespace: webapp
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
            name: my-webapp
            port:
              number: 80
```

## Auto Scaling

### Cluster Autoscaler

Scale EC2 nodes based on pod scheduling failures:

```bash
# Install cluster autoscaler
kubectl apply -f https://www.k8s.io/autoscaler/releases/cluster-autoscaler-chart/latest/cluster-autoscaler.yaml

# Configure AWS Node Group scaling
aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?contains(Tags[?Key=='eks:cluster-name'],'my-cluster')]"
```

### Karpenter (Recommended)

Karpenter is EKS's built-in autoscaler that provisions right-sized nodes:

```bash
# Install Karpenter
helm install karpenter karpenter -n kube-system --repo https://charts.karpenter.sh

# Provisioner
kubectl apply -f - <<EOF
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: "node.kubernetes.io/instance-type"
      operator: In
      values: ["m5.large", "m5.xlarge"]
    - key: "topology.kubernetes.io/zone"
      operator: In
      values: ["us-east-1a", "us-east-1b"]
  provider:
    amiFamily: AL2
  ttlSecondsAfterIdle: 300
EOF
```

## Networking

### Security Groups for Nodes

Nodes need SG rules for:
- Port 443 (control plane → node)
- Port 10250 (kubelet API)
- Port 8472 (VXLAN for pod networking, CNI)

```bash
# Node SG must allow:
# - Inbound 443 from EKS control plane
# - Inbound 10250 from within VPC
# - Inbound 8472 from within VPC (CNI)
```

### Pod Networking

Pods on Fargate get IP from VPC subnet. Pods on EC2 use VPC CNI (secondary ENIs).

## Monitoring

```bash
# CloudWatch Container Insights
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name eks-pod-identity-agent \
  --addon-version latest

# Fluent Bit (logs)
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest/templates/deployment.yaml
```

## EKS Pricing

- Control plane: $0.10/hour per cluster ($73/month)
- Fargate: pay for pod resources (vCPU + memory)
- EC2 node groups: pay for EC2 instances
- No charge for managed add-ons

## References

- **Homepage:** https://aws.amazon.com/eks/
- **Documentation:** https://docs.aws.amazon.com/eks/
- **Pricing:** https://aws.amazon.com/eks/pricing/

## Pricing Examples

**Scenario 1:** A production EKS cluster (1.29) running 24/7. Control plane: $0.10/hr × 24 × 30 = $72/month. 9 m5.xlarge nodes (3 AZs × 3): 36 vCPU × $0.192/hr (Linux) × 24hr × 30 = $4,966/month. Total: ~$5,038/month. With 3-year Reserved Instances: $0.096/hr × 36 × 24 × 30 = $2,483/month. Total with RI: ~$2,555/month.

**Scenario 2:** A dev environment with EKS (Fargate only, no EC2). Control plane: $72/month. Fargate pods (1 vCPU, 2GB, 8hr/day): 8hr × 30 days × 0.5 vCPU × $0.04048 + 8hr × 30 × 2GB × $0.00444 = $5.38/month. Total: ~$77/month vs EC2-based EKS (~$200+/month for 3 m5.large).

## Nuggets & Gotchas

- **EKS node security groups must allow port 443 from the control plane — without it, nodes can't register:** If your nodes are `NotReady`, check the SG rules. The EKS documentation has the exact SG configuration required.
- **Fargate pods are assigned a separate IAM role (IRSA) — not the node role:** If your Fargate pod needs AWS permissions, you must create a ServiceAccount with an IAM role annotation. The node role is not accessible to Fargate pods.
- **Karpenter and Cluster Autoscaler conflict — use one or the other:** If you install both, they'll fight over node provisioning. Use Karpenter for new clusters (it's AWS's recommended approach). Migrate from Cluster Autoscaler by uninstalling it first.
- **The VPC CNI creates secondary ENIs — each ENI has a limit on IP addresses:** A `m5.xlarge` has a primary ENI + 3 secondary ENIs. With 15 IPs per ENI = 60 pods max. For more pods, use larger instances or enable prefix delegation (assign /28 subnets per ENI).
- **EKS add-ons are upgraded automatically by AWS (minor versions) — but you can pin to a version:** If you need to test upgrades before they auto-apply, pin the add-on version. Unpinning is required to resume auto-upgrades.