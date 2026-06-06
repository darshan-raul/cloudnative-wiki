---
title: Amazon ECS
description: Amazon ECS — Docker container orchestrator on EC2 or Fargate. Clusters, task definitions, services, tasks, container definitions, and IAM roles for tasks.
tags:
  - aws
  - compute
  - containers
  - ecs
---

# Amazon ECS (Elastic Container Service)

ECS is AWS's native container orchestrator. It manages Docker containers on a cluster of EC2 instances (or Fargate serverless). ECS is simpler than EKS — it doesn't require Kubernetes knowledge, integrates deeply with AWS services, and has a simpler IAM model for task roles.

## Core Concepts

### Architecture

```
ECS Cluster (ec2 or fargate)
  ├── EC2 Instance (self-managed) or Fargate (serverless)
  │     └── Container Instance (ECS Agent running)
  │           ├── Task A
  │           │     ├── Container 1 (nginx)
  │           │     └── Container 2 (app)
  │           └── Task B
  │                 └── Container 1 (worker)
  │
  └── ECS Service (maintains desired task count)
```

### Key Terms

| Term | Description |
|------|-------------|
| Cluster | Logical grouping of container instances |
| Task Definition | Blueprint for a task (container configs) |
| Task | Running instance of a task definition |
| Service | Maintains N running tasks (like a ReplicaSet) |
| Container Instance | EC2 instance with ECS Agent |
| Task Role | IAM role for a task's containers |

## Launch Types

### EC2 (Self-Managed)

You manage EC2 instances as container hosts. More control, cheaper for long-running clusters.

```
┌─────────────────────────────────────┐
│  ECS Cluster (EC2 Launch Type)      │
│                                     │
│  ┌──────────────┐  ┌──────────────┐ │
│  │  EC2 Instance │  │  EC2 Instance │ │
│  │  ┌─────────┐ │  │  ┌─────────┐ │ │
│  │  │  Task A │ │  │  │  Task B │ │ │
│  │  └─────────┘ │  │  └─────────┘ │ │
│  └──────────────┘  └──────────────┘ │
│                                     │
│  You manage: EC2 provisioning,     │
│  scaling, patching                  │
└─────────────────────────────────────┘
```

### Fargate (Serverless)

AWS manages the underlying infrastructure. You specify CPU/memory and ECS handles the rest.

```
┌─────────────────────────────────────┐
│  ECS Cluster (Fargate Launch Type)  │
│                                     │
│  Task A  ←─── AWS manages infra     │
│  Task B  ←─── Auto-scales, no EC2   │
│                                     │
│  You pay per task second            │
└─────────────────────────────────────┘
```

## Task Definitions

```json
{
  "family": "my-web-app",
  "containerDefinitions": [
    {
      "name": "nginx",
      "image": "nginx:1.25",
      "portMappings": [{"containerPort": 80, "protocol": "tcp"}],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/my-web-app",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "nginx"
        }
      }
    },
    {
      "name": "app",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:latest",
      "portMappings": [{"containerPort": 8080}],
      "essential": true,
      "dependsOn": [{"containerName": "nginx", "condition": "HEALTHY"}],
      "environment": [
        {"name": "DATABASE_URL", "value": "postgres://db:5432/app"}
      ]
    }
  ],
  "cpu": "256",
  "memory": "512"
}
```

### Registering a Task Definition

```bash
aws ecs register-task-definition \
  --family my-web-app \
  --container-definitions file://task-definition.json
```

## Running Tasks

### Run a Task (one-off)

```bash
aws ecs run-task \
  --cluster my-cluster \
  --task-definition my-web-app:1 \
  --network-configuration '{
    "awsvpcConfiguration": {
      "subnets": ["subnet-xxxxx"],
      "securityGroups": ["sg-xxxxx"]
    }
  }'
```

### Create a Service (continuous)

```bash
aws ecs create-service \
  --cluster my-cluster \
  --service-name my-web-service \
  --task-definition my-web-app:1 \
  --desired-count 3 \
  --launch-type FARGATE \
  --network-configuration '{
    "awsvpcConfiguration": {
      "subnets": ["subnet-xxxxx", "subnet-yyyyy"],
      "securityGroups": ["sg-xxxxx"]
    }
  }' \
  --load-balancers '[{
    "targetGroupArn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/ecs-target/abc123",
    "containerName": "nginx",
    "containerPort": 80
  }]'
```

## IAM Roles for Tasks

### Task Role (application permissions)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "dynamodb:GetItem"],
    "Resource": "*"
  }]
}
```

```bash
aws iam create-role \
  --role-name ecs-task-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'
```

### Instance Role (container host permissions)

The EC2 instance profile needs `ecsAgent` permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ecs:DeregisterContainerInstance",
      "ecs:RegisterContainerInstance",
      "ecs:UpdateContainerInstances",
      "ecs:Poll"
    ],
    "Resource": "*"
  }]
}
```

## Auto Scaling

### Service Auto Scaling

```bash
aws application-autoscaling register-scalable-target \
  --namespace ecs \
  --resource-id service/my-cluster/my-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10

aws application-autoscaling put-scaling-policy \
  --namespace ecs \
  --resource-id service/my-cluster/my-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cpu-70 \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70,
    "PredefinedMetricSpecification": {"PredefinedMetricType": "ECSServiceAverageCPUUtilization"}
  }'
```

## Logs

### CloudWatch Logs (awslogs driver)

```json
{
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/my-app",
      "awslogs-region": "us-east-1",
      "awslogs-stream-prefix": "my-app"
    }
  }
}
```

View logs:
```bash
aws logs describe-log-groups --log-group-name /ecs/my-app
aws logs filter-log-events --log-group-name /ecs/my-app --filter-pattern "ERROR"
```

## Service Discovery

For services to find each other without hard-coded IPs:

```bash
aws servicediscovery create-service \
  --name my-service \
  --namespace-id ns-xxxxx \
  --dns-config '{"NamespaceId": "ns-xxxxx", "RoutingPolicy": "MULTIVALUE"}'
```

Tasks register with Route 53 auto-discovery (e.g., `my-service.demo.local`).

## Updates and Rolling Deployments

```bash
# Update service (rolling deployment)
aws ecs update-service \
  --cluster my-cluster \
  --service my-web-service \
  --task-definition my-web-app:2

# Check deployment status
aws ecs describe-services \
  --cluster my-cluster \
  --services my-web-service
```

### Deployment Configuration

```bash
aws ecs update-service \
  --cluster my-cluster \
  --service my-web-service \
  --deployment-controller type=CODE_DEPLOY \
  --deployment-configuration '{
    "maximumPercent": 200,
    "minimumHealthyPercent": 100
  }'
```

## Comparing ECS and EKS

| | ECS | EKS |
|--|--|--|
| Control plane | Managed (AWS) | Managed Kubernetes API |
| Worker nodes | EC2 or Fargate | EC2 or Fargate |
| YAML format | Task definitions (JSON) | Kubernetes manifests |
| Ingress | ALB (native integration) | ALB/Ingress (extra config) |
| IAM for workloads | Task Role (simple) | IRSA (Kubernetes RBAC + IAM) |
| Use if | Simpler, AWS-native | Already know Kubernetes |

## References

- **Homepage:** https://aws.amazon.com/ecs/
- **Documentation:** https://docs.aws.amazon.com/ecs/
- **Pricing:** https://aws.amazon.com/ecs/pricing/

## Pricing Examples

**Scenario 1:** A production API with 3 tasks on Fargate (1 vCPU, 2GB each), running 24/7. Fargate pricing: 1 vCPU = $0.04048/hr, 2GB = $0.00444/hr per task. 3 tasks × ($0.04048 + $0.00444×2) = 3 × $0.04936 = $0.148/hr × 24 × 30 = $106.70/month.

**Scenario 2:** The same API on EC2 (3 m5.large = 2 vCPU, 8GB each). m5.large on-demand: $0.096/hr × 3 = $0.288/hr × 24 × 30 = $207.36/month. Plus EBS (100GB gp3): 300GB × $0.08 = $24/month. Total: $231/month. Fargate is 54% cheaper and requires no EC2 management.

## Nuggets & Gotchas

- **ECS tasks are not automatically registered to ALB target groups — you must specify `--load-balancers` when creating a service:** Without this, your containers will run but won't receive traffic. Always configure the load balancer target group when creating a service for a web application.
- **ECS task role (IAM) is per-task, not per-container — all containers in a task share the same role:** If your sidecar container needs different permissions than your main container, either split into two tasks or use task role permissions that cover both.
- **Fargate tasks can't use instance store volumes — only EFS or bind mounts:** If your application needs temporary storage (e.g., `/tmp`), Fargate provides 200GB ephemeral storage by default (from `/proc/sys/fs/aio-nr`). For persistent storage between task runs, use EFS.
- **ECS agent on EC2 must be up-to-date — old agent versions have bugs with new task definition features:** If your task definition with new features (e.g., firelens log routing) doesn't work, check the ECS agent version on your container instance and update it.
- **ECS service auto scaling uses CloudWatch metrics — if your app doesn't emit metrics, CPU utilization won't be visible:** For Fargate, ensure your containers emit CloudWatch metrics or use the `ECSServiceAverageCPUUtilization` metric. If your app is I/O bound (not CPU bound), use a custom metric or target tracking on a different metric.