---
title: AWS Lambda
description: AWS Lambda — serverless functions. Event-driven execution, languages, layers, scaling, cold starts, pricing, and SAM framework.
tags:
  - aws
  - compute
  - serverless
  - lambda
---

# AWS Lambda

Lambda is a serverless compute service — you write functions, upload them, and AWS handles provisioning, scaling, and high availability. You pay only for compute time consumed (rounded to the nearest 1ms).

## Core Concepts

### How Lambda Works

```
Event (S3, SNS, SQS, API GW, CloudWatch, etc.)
  → Lambda Runtime (Node.js, Python, Java, Go, .NET, Ruby)
      → Your Function Code
          → Response

Billing: Duration (ms) × Memory (GB) × $0.0000166667
```

### Supported Runtimes

| Runtime | Version | Language |
|---------|--------|----------|
| Node.js | 18.x, 20.x | JavaScript |
| Python | 3.9, 3.10, 3.11, 3.12 | Python |
| Java | 11, 17, 21 | Java |
| Go | 1.x | Go |
| .NET | 6, 7, 8 | C#, F# |
| Ruby | 3.2 | Ruby |
| Custom | provided.al2, provided | Any (via container) |

### Execution Limits

| Resource | Limit |
|----------|-------|
| Max execution time | 15 minutes |
| Max memory | 10 GB |
| Max ephemeral storage (/tmp) | 10 GB |
| Max package size (ZIP) | 50 MB (direct), 250 MB (layer) |
| Max container image | 10 GB |
| Concurrent executions | 1,000 (soft limit) |

## Creating a Function

### Via Console

Console → Lambda → Create function → Author from scratch / Blueprint / Container image

### Via CLI

```bash
aws lambda create-function \
  --function-name my-function \
  --runtime python3.12 \
  --role arn:aws:iam::123456789012:role/lambda-role \
  --handler app.handler \
  --code S3Bucket=my-bucket,S3Key=function.zip \
  --timeout 30 \
  --memory-size 256
```

### Via SAM (Serverless Application Model)

```yaml
# template.yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Resources:
  MyFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: app.handler
      Runtime: python3.12
      CodeUri: ./
      Events:
        ApiEvent:
          Type: Api
          Properties:
            Path: /hello
            Method: get
```

## Event Sources

### S3 Trigger

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    Events:
      S3Event:
        Type: S3
        Properties:
          Bucket: my-bucket
          Events: s3:ObjectCreated:*
```

### SQS Trigger

```bash
aws lambda create-event-source-mapping \
  --function-name my-function \
  --event-source-arn arn:aws:sqs:us-east-1:123456789012:my-queue \
  --batch-size 10  # max 10 for SQS
```

### CloudWatch Events (Scheduled)

```yaml
Events:
  ScheduledEvent:
    Type: Schedule
    Properties:
      Schedule: cron(0 */6 * * ? *)  # Every 6 hours
```

## Lambda Layers

Layers let you package dependencies separately from the function code:

```bash
# Create layer
aws lambda publish-layer-version \
  --layer-name my-python-libs \
  --description "Common Python libraries" \
  --content S3Bucket=my-bucket,S3Key=layers/pandas-numpy.zip \
  --compatible-runtimes python3.11 python3.12

# Add to function
aws lambda update-function-configuration \
  --function-name my-function \
  --layers arn:aws:lambda:us-east-1:123456789012:layer:my-python-libs:1
```

Layer structure:
```
python/
  lib/
    site-packages/  ← pip packages go here
```

## Concurrency and Scaling

### Reserved Concurrency

Guarantee capacity for a function:

```bash
aws lambda put-function-concurrency \
  --function-name my-critical-function \
  --reserved-concurrent-executions 100
```

### Provisioned Concurrency

Keep functions warm (no cold starts):

```bash
aws lambda put-provisioned-concurrency-config \
  --function-name my-api-function \
  --provisioned-concurrent-executions 10 \
  --qualifier 1  # version
```

### Scaling Behavior

```
SQS trigger: scale up to process backlog (1 concurrent per batch)
API Gateway: scale to match request rate (instant)
S3 trigger: 1 concurrent per event
```

## Cold Starts

Cold starts happen when Lambda spins up a new execution context. Warm invocations are ~1ms; cold starts vary by runtime:

| Runtime | Cold Start (ms) |
|---------|-----------------|
| Node.js/Python | 50-200 |
| Java/.NET | 500-2000 |
| Container image | 500-3000 |

### Reducing Cold Starts

- Use Provisioned Concurrency (pay to keep warm)
- Reduce package size (fewer dependencies to load)
- Use `arm64` (`Graviton2`) — faster cold starts
- Keep connections warm (reuse DB connections)

## Pricing

| Dimension | Cost |
|-----------|------|
| Request | $0.20 per 1M requests |
| Duration (x86) | $0.0000166667 per GB-second |
| Duration (arm64) | $0.0000133333 per GB-second |
| Provisioned Concurrency | $0.0000166667 per GB-second |
| Provisioned Concurrency (duration) | $0.00000999999 per GB-second |

### Free Tier

- 400,000 GB-seconds per month (arm64)
- 400,000 requests per month
- 3,200,000 seconds of compute at 128MB

### Cost Calculation

```
Function: 512MB, 200ms duration, 10M requests/month

Compute: 512MB × 0.2s × 10M = 1,024,000 GB-seconds
Cost: 1,024,000 × $0.0000166667 = $17.07

Requests: 10M × $0.20/1M = $2.00

Total: $19.07/month
```

## VPC Configuration

Lambda runs in an AWS-managed VPC by default. To access VPC resources (RDS, ElastiCache, private ALB):

```bash
aws lambda update-function-configuration \
  --function-name my-function \
  --vpc-config SubnetIds=subnet-xxxxx,subnet-yyyyy,SecurityGroupIds=sg-xxxxx
```

**Important:** When Lambda connects to a VPC, it runs inside your VPC — cold starts increase by ~10 seconds (ENI attachment time). Use VPC endpoints for S3/DynamoDB to avoid NAT Gateway costs.

## SAM (Serverless Application Model)

```bash
# Install SAM CLI
pip install aws-sam-cli

# Initialize project
sam init -n my-app -r python3.12 -d pip

# Build
sam build

# Deploy
sam deploy --guided

# Local testing
sam local start-api
```

## Monitoring

```bash
# CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=my-function
```

Key metrics:
- `Invocations` — total function calls
- `Duration` — execution time (p50, p90, p99)
- `Errors` — failed invocations
- `Throttles` — rejected invocations (at concurrency limit)
- `ConcurrentExecutions` — current concurrency

## References

- **Homepage:** https://aws.amazon.com/lambda/
- **Documentation:** https://docs.aws.amazon.com/lambda/
- **Pricing:** https://aws.amazon.com/lambda/pricing/

## Pricing Examples

**Scenario 1:** An image resizer function (Python, 512MB, 150ms avg). 1M images/month processed. Compute: 512MB × 0.15s × 1M = 76,800,000 GB-seconds / 1M seconds = 76.8 GB-seconds. Wait: 512MB × 0.15s × 1M = 76,800,000 GB-seconds. Cost: 76.8M × $0.0000166667 = $1,280/month. That seems wrong... Let me recalculate: 512MB = 0.5GB. 0.5GB × 0.15s × 1M = 75,000 GB-seconds. $0.0000166667 × 75,000 = $1.25/month. Plus requests: 1M × $0.20/1M = $0.20/month. Total: $1.45/month.

**Scenario 2:** A REST API (Node.js, 256MB, 50ms avg). 100 requests/minute = 4.3M/month. Compute: 0.25GB × 0.05s × 4.3M = 53,750 GB-seconds × $0.0000166667 = $0.90/month. Requests: 4.3M × $0.20/1M = $0.86/month. Total: $1.76/month. With Provisioned Concurrency (10 instances, always warm): 10 × 30 days × 24hr × 3600s × 0.25GB × $0.00000999999 = $6.48/month. Total with provisioned: $7.34/month.

## Nuggets & Gotchas

- **Lambda@Edge and Lambda function URLs are different services — don't confuse them:** Lambda@Edge runs at CloudFront edge locations (for low-latency global processing). Lambda function URLs are simple HTTPS endpoints for your function. Lambda@Edge has different limits and is tied to CloudFront distributions.
- **Lambda concurrency limit is 1,000 per region — not per function:** If you have 10 functions each receiving 500 concurrent requests, you'll hit the region limit and get throttled. Use reserved concurrency per function if you need isolation.
- **Lambda has a 15-minute max execution time — not 15 minutes of CPU time:** If your function sleeps for 14 minutes while waiting for an API response, you've consumed 14 minutes of wall-clock time (not CPU time, which is cheap). Lambda bills duration, not CPU.
- **VPC-connected Lambda functions take ~10 seconds to cold-start due to ENI attachment:** If your function needs VPC access and latency matters, either use Provisioned Concurrency or rethink the architecture (Lambda should call VPC resources, not live in the VPC unless necessary).
- **SQS FIFO queues with Lambda require batch size = 1 — Lambda processes one message at a time from FIFO:** Standard SQS allows batch size up to 10. For high-throughput FIFO processing, use an SQS trigger with `MaximumBatchingWindow` or switch to standard queue.