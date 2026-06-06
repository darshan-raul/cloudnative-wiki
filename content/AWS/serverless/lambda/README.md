---
title: AWS Lambda
description: AWS Lambda — serverless functions. Runtime support, event handlers, layers, versions, aliases, environment variables, VPC networking, cold starts, and cost.
tags:
  - aws
  - serverless
  - lambda
  - functions
---

# AWS Lambda

Lambda is a serverless compute service. Upload your code (or bring a container) and Lambda runs it in response to events — no servers to manage, auto-scales to zero, pay per millisecond.

## Runtimes

| Runtime | Version |
|---------|---------|
| Node.js | 18.x, 20.x, 22.x |
| Python | 3.9, 3.10, 3.11, 3.12 |
| Java | 11, 17, 21 |
| .NET | 6, 8 |
| Ruby | 3.2 |
| Go | 1.x |
| Custom Runtime | Bring your own |

## Creating a Function

```bash
# Create function
aws lambda create-function \
  --function-name my-function \
  --runtime python3.12 \
  --role arn:aws:iam::123456789012:role/lambda-role \
  --handler app.handler \
  --zip-file fileb://function.zip \
  --timeout 30 \
  --memory-size 256

# Upload new code
aws lambda update-function-code \
  --function-name my-function \
  --zip-file fileb://function.zip
```

## Writing Functions

### Python

```python
import json
import boto3

def handler(event, context):
    # event contains the trigger data
    print(f"Received event: {json.dumps(event)}")
    
    # context has runtime info
    print(f"Function: {context.function_name}")
    print(f"Memory: {context.memory_limit_in_mb}")
    print(f"Request ID: {context.aws_request_id")
    
    # Your logic here
    result = process(event)
    
    return {
        'statusCode': 200,
        'body': json.dumps(result)
    }

def process(event):
    # Business logic
    return {'message': 'success', 'data': event.get('data')}
```

### Node.js

```javascript
exports.handler = async (event, context) => {
    console.log(`Received event: ${JSON.stringify(event)}`);
    
    const result = await processEvent(event);
    
    return {
        statusCode: 200,
        body: JSON.stringify(result)
    };
};

async function processEvent(event) {
    // Business logic
    return { message: 'success', data: event.data };
}
```

## Event Sources

### S3 Trigger

```python
def handler(event, context):
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        print(f"New file: {bucket}/{key}")
        process_file(bucket, key)
```

### DynamoDB Stream

```python
def handler(event, context):
    for record in event['Records']:
        if record['eventName'] == 'INSERT':
            item = record['dynamodb']['NewImage']
            print(f"New item: {item}")
        elif record['eventName'] == 'MODIFY':
            old = record['dynamodb']['OldImage']
            new = record['dynamodb']['NewImage']
            print(f"Updated: {old} -> {new}")
        elif record['eventName'] == 'REMOVE':
            old = record['dynamodb']['OldImage']
            print(f"Deleted: {old}")
```

### SQS Trigger

```python
def handler(event, context):
    for record in event['Records']:
        body = json.loads(record['body'])
        print(f"Processing: {body}")
        process_message(body)
    
    return {'processed': len(event['Records'])}
```

## Versions and Aliases

```bash
# Publish version (immutable)
aws lambda publish-version --function-name my-function
# Returns: Version: 3

# Create alias
aws lambda create-alias \
  --function-name my-function \
  --name production \
  --function-version 3 \
  --description "Production alias"

# Update alias to point to new version
aws lambda update-alias \
  --function-name my-function \
  --name production \
  --function-version 4
```

```
production alias ──► Version 3 ──► $LATEST
                                      │
              Version 2 ◄────────────┘
              Version 1
```

## Layers

```bash
# Create layer
aws lambda publish-layer-version \
  --layer-name my-layer \
  --description "Common utilities" \
  --license-info "MIT" \
  --content fileb://layer.zip \
  --compatible-runtimes python3.12

# Add to function
aws lambda update-function-configuration \
  --function-name my-function \
  --layers "arn:aws:lambda:us-east-1:123456789012:layer:my-layer:1"
```

## Environment Variables

```bash
# Set environment variables
aws lambda update-function-configuration \
  --function-name my-function \
  --environment 'Variables={ENV=production,DATABASE_URL=my-db.example.com}'

# Encryption at rest (AWS managed key)
aws lambda update-function-configuration \
  --function-name my-function \
  --kms-key-arn arn:aws:kms:us-east-1:123456789012:key/xxxxx
```

## VPC Networking

```python
# Lambda in VPC (for RDS, ElastiCache access)
# VPC config via CLI:
aws lambda update-function-configuration \
  --function-name my-function \
  --vpc-config '{
    "SubnetIds": ["subnet-xxxxx", "subnet-yyyyy"],
    "SecurityGroupIds": ["sg-xxxxx"]
  }'
```

**Note:** Lambda in VPC adds 10-30 second cold start (ENI attachment).

## Concurrency Control

```bash
# Reserved concurrency (guarantee capacity)
aws lambda put-function-concurrency \
  --function-name my-function \
  --reserved-concurrent-executions 100

# Provisioned concurrency (pre-warmed)
aws lambda put-provisioned-concurrency-config \
  --function-name my-function \
  --qualifier alias-or-version \
  --provisioned-concurrent-executions 10
```

## Cost

| Component | Cost |
|-----------|------|
| Requests | $0.20/million |
| Duration (GB-second) | $0.0000166667/GB-second |
| Provisioned concurrency | $0.000015/GB-second |
| Duration (ARM Graviton2) | 20% cheaper |

**Free tier:** 400K GB-seconds and 1M requests/month.

## Pricing Example

```
Lambda with 512MB memory, 1 second execution:

Duration: 512MB × 1s = 0.5 GB-second
Price: 0.5 GB-second × $0.0000166667 = $0.0000083 per call

1M requests/month = 1,000,000 × $0.20/million = $0.20 (requests)
                   1,000,000 × 0.5 GB-second × $0.0000166667 = $8.33 (duration)
Total: $8.53/month
```

## Limits

| Resource | Limit |
|----------|-------|
| Memory | 128MB to 10GB |
| Timeout | Up to 15 minutes |
| Deployment package | 50MB (zipped), 250MB (uncompressed) |
| Concurrent executions | 1000 (default, adjustable) |
| Event size | 6MB (sync), 256KB (async) |

## References

- **Homepage:** https://aws.amazon.com/lambda/
- **Documentation:** https://docs.aws.amazon.com/lambda/
- **Pricing:** https://aws.amazon.com/lambda/pricing/

## Nuggets & Gotchas

- **Lambda has a 15-minute maximum execution time — it WILL timeout if your function runs longer:** If you need 20+ minute execution, break into Step Functions steps or use ECS/Fargate. Lambda is designed for short-running tasks.
- **Lambda cold starts in a VPC are 10-30 seconds — your users will notice:** VPC networking requires ENI attachment, which is slow on cold start. For latency-sensitive VPC workloads, use provisioned concurrency or move to a public subnet.
- **Lambda ARM/Graviton2 is 20% cheaper and often faster — prefer `nodejs20.x` or Python 3.12 on ARM:** Graviton2 functions cost less and have better performance for most workloads. Only use x86 if you have native dependencies that don't support ARM.
- **Lambda's concurrent execution limit is shared across ALL functions in an account — one function hogging resources affects others:** Set reserved concurrency per function to guarantee capacity. Without it, one runaway function can throttle all others.
- **Lambda layers are NOT automatically updated — if you update a layer, you must re-deploy functions to pick up changes:** Layers are immutable once published. Updating the layer version doesn't update existing functions. You must `update-function-configuration` on each function.