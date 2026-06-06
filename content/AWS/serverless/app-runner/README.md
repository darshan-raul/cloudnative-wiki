---
title: AWS App Runner
description: AWS App Runner — managed container web apps and APIs. No ECS/EKS knowledge required. Connect to source code or container image, auto-scaling, SSL, and built-in observability.
tags:
  - aws
  - serverless
  - apprunner
  - containers
---

# AWS App Runner

App Runner runs web apps and APIs as containers without requiring ECS/EKS clusters. Provide a container image or source code repository, and App Runner handles deployment, scaling, SSL termination, and load balancing.

## When to Use App Runner

```
Need to run a web app/container?
  │
  ├── Simple web app (no K8s knowledge needed)
  │   └── App Runner ✓ (simplest option)
  │
  ├── Microservices with service mesh
  │   └── ECS Fargate or EKS
  │
  ├── Long-running background tasks
  │   └── ECS Fargate (not App Runner)
  │
  └── GPU workloads
      └── EC2 or ECS Fargate (not App Runner)
```

## App Runner vs Others

| Feature | App Runner | ECS Fargate | Lambda |
|---------|------------|-------------|--------|
| Container support | Yes | Yes | No (zip/Image) |
| Serverless | Yes (pay-per-use) | Yes (pay-per-use) | Yes (pay-per-request) |
| Autoscaling | Built-in | Manual | Automatic |
| HTTPS | Automatic | Manual (ALB) | API Gateway |
| Long-running | Yes | Yes | Max 15 min |
| Custom networking | VPC | VPC | VPC |
| Cost (small app) | ~$15/month | ~$25/month | ~$0/month (low traffic) |

## Creating from Container Image

```bash
# Create App Runner service
aws apprunner create-service \
  --service-name my-app \
  --source-configuration '{
    "ImageRepository": {
      "ImageIdentifier": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-image:latest",
      "ImageRepositoryType": "ECR",
      "ImageConfiguration": {
        "Port": "8080",
        "RuntimeEnvironmentVars": [
          {"Key": "ENV", "Value": "production"}
        ]
      }
    },
    "AutoDeploymentsEnabled": true
  }' \
  --instance-configuration '{
    "Cpu": "1 vCPU",
    "Memory": "2 GB"
  }' \
  --health-check-configuration '{
    "Protocol": "TCP",
    "Path": "/health",
    "Interval": 10,
    "Timeout": 5,
    "HealthyThreshold": 3,
    "UnhealthyThreshold": 3
  }'
```

### ECR Image Requirements

```bash
# Build and push image
aws ecr create-repository --repository-name my-app

docker build -t my-app .
docker tag my-app 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:latest
aws ecr get-login-password | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:latest
```

## Creating from Source Code

```bash
# Create service from source (GitHub)
aws apprunner create-service \
  --service-name my-app \
  --source-configuration '{
    "AutoDeploymentsEnabled": true,
    "AuthenticationConfiguration": {
      "ConnectionArn": "arn:aws:apprunner:us-east-1:123456789012:connection/my-github/xxxxx"
    },
    "CodeRepository": {
      "CodeConfiguration": {
        "ConfigurationSource": "API",
        "CodeConfigurationValues": {
          "Runtime": "PYTHON_3",
          "BuildCommand": "pip install -r requirements.txt",
          "StartCommand": "python app.py",
          "Port": "8080"
        }
      },
      "RepositoryUrl": "https://github.com/my-org/my-app",
      "SourceCodeVersion": {"Type": "BRANCH", "Value": "main"}
    }
  }'
```

## Autoscaling

```bash
# Configure auto-scaling
aws apprunner update-service \
  --service-arn arn:aws:apprunner:us-east-1:123456789012:service/my-app/xxxxx \
  --auto-scaling-configuration-arn arn:aws:apprunner:us-east-1::auto-scaling-configuration/HighAvailability/arn

# Or create custom config
aws apprunner create-auto-scaling-configuration \
  --max-size 10 \
  --min-size 2 \
  --desired-size 2
```

## Custom Domain

```bash
# Add custom domain
aws apprunner associate-custom-domain \
  --service-arn arn:aws:apprunner:us-east-1:123456789012:service/my-app/xxxxx \
  --domain-name myapp.example.com

# DNS: CNAME to the App Runner domain
# App Runner handles SSL automatically
```

## Environment Variables

```bash
# Add environment variables
aws apprunner update-service \
  --service-arn arn:aws:apprunner:us-east-1:123456789012:service/my-app/xxxxx \
  --source-configuration '{
    "EnvironmentVariables": {
      "DATABASE_URL": "postgres://...",
      "API_KEY": "secret"
    }
  }'

# Secrets (from Parameter Store or Secrets Manager)
aws apprunner update-service \
  --service-arn arn:aws:apprunner:us-east-1:123456789012:service/my-app/xxxxx \
  --encryption-configuration '{
    "KmsKey": "arn:aws:kms:us-east-1:123456789012:key/xxxxx"
  }'
```

## VPC Support

```bash
# Run in VPC (access RDS, ElastiCache)
aws apprunner update-service \
  --service-arn arn:aws:apprunner:us-east-1:123456789012:service/my-app/xxxxx \
  --network-configuration '{
    "EgressType": "VPC",
    "VpcConnectorArn": "arn:aws:apprunner:us-east-1:123456789012:vpc-connector/my-connector/xxxxx"
  }'

# Create VPC connector
aws apprunner create-vpc-connector \
  --vpc-connector-name my-connector \
  --subnets subnet-xxxxx subnet-yyyyy subnet-zzzzz \
  --security-groups sg-xxxxx
```

## Observability

```bash
# View logs (CloudWatch)
aws logs tail /aws/apprunner/my-app --follow

# Get service events
aws apprunner describe-service --service-arn arn:aws:apprunner:...
```

## Pricing

| Resource | Cost |
|----------|------|
| vCPU (per hour) | $0.05/vCPU-hour |
| Memory (per hour) | $0.006/GB-hour |
| Build (optional) | $0.005/vCPU-minute |
| Active connections | Free |

**Example:** 2 vCPU, 4GB instance, 1 instance running 24/7:
- vCPU: 2 × $0.05 × 24 × 30 = $72/month
- Memory: 4 × $0.006 × 24 × 30 = $17.28/month
- Total: ~$89/month

With auto-scaling (2 instances average, burst to 5):
- Average: ~$89/month
- With burst: $89 × 2.5 = ~$220/month

## Limits

| Resource | Limit |
|----------|-------|
| Concurrent instances | 25 |
| vCPU per instance | 1-4 |
| Memory per instance | 2-8 GB |
| Request timeout | 15 seconds |
| Deployment timeout | 30 minutes |

## References

- **Homepage:** https://aws.amazon.com/apprunner/
- **Documentation:** https://docs.aws.amazon.com/apprunner/
- **Pricing:** https://aws.amazon.com/apprunner/pricing/

## Nuggets & Gotchas

- **App Runner has a 15-second request timeout — long-running requests will fail:** If your requests take > 15 seconds, App Runner returns a 503. Use async patterns (queue with SQS) or ECS Fargate for long-running tasks.
- **App Runner auto-scales based on concurrent requests — if your app is single-threaded, set min instances to 1:** App Runner scales based on concurrency. A single-threaded Node.js app with 50 concurrent requests will queue them, not scale out. Set `min-size` to match your expected concurrency.
- **App Runner's VPC connector only supports egress — your app CAN reach VPC resources, but inbound traffic still goes through App Runner's public endpoint:** You can't use App Runner as a private-only service. All traffic enters via App Runner's public URL, then can be routed to VPC.
- **App Runner builds from source code in App Runner's build infrastructure — not your local machine:** If you need custom build environments (multi-stage Docker, specific toolchains), use a container image from ECR instead of source code.
- **App Runner's built-in observability is minimal — you get CloudWatch logs but no distributed tracing:** For production debugging, add X-Ray SDK to your app. App Runner doesn't auto-instrument like Lambda@Edge would.