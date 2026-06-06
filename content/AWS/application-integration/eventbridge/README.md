---
title: Amazon EventBridge
description: Amazon EventBridge — serverless event bus. Default/custom/event buses, rules, schema registry, SaaS ingestion, replay, event replay, and cross-account event delivery.
tags:
  - aws
  - application-integration
  - eventbridge
  - event-driven
---

# EventBridge

EventBridge is a serverless event bus that routes events from AWS services, SaaS applications, and custom applications to targets. Unlike SNS (pub/sub), EventBridge uses rules for content-based filtering and supports schema registry for event discovery.

## Three Types of Event Buses

```
AWS Services Event Bus (default)
  │ All AWS service events (CloudTrail, Config, etc.)
  ▼
Custom Event Bus
  │ Your applications publish here
  ▼
SaaS Event Bus (Partner Event Bus)
  │ Third-party SaaS (Datadog, Shopify, etc.)
  ▼
```

## Event Bus Operations

```bash
# Create custom event bus
aws events create-event-bus \
  --name my-event-bus \
  --description "My custom event bus"

# Create partner event bus (for SaaS)
aws events create-partner-event-bus \
  --name datadog-events \
  --event-source-name aws.partner/datadog.com

# List event buses
aws events list-event-buses

# Put permission for cross-account delivery
aws events put-permission \
  --event-bus-name my-event-bus \
  --action events:PutEvents \
  --principal 123456789012
```

## Event Structure

```json
{
  "id": "def258f0-1234-5678-abcd-example",
  "version": "1",
  "account": "123456789012",
  "time": "2024-01-15T10:30:00Z",
  "region": "us-east-1",
  "detail-type": "OrderShipped",
  "source": "com.mycompany.orders",
  "resources": ["arn:aws:ec2:us-east-1:123456789012:instance/i-xxxxx"],
  "detail": {
    "order_id": "ORD-12345",
    "customer_id": "CUST-67890",
    "total": 99.99,
    "status": "shipped"
  }
}
```

## Publishing Events

```python
import boto3
import json

events = boto3.client('events')

# Publish to default event bus
response = events.put_events(
    Entries=[
        {
            'Source': 'com.mycompany.orders',
            'DetailType': 'OrderShipped',
            'Detail': json.dumps({'order_id': '12345', 'status': 'shipped'}),
            'Resources': ['arn:aws:ec2:us-east-1:123456789012:instance/i-xxxxx']
        }
    ]
)
print(f"Failed: {response['FailedEntryCount']}")

# Publish to custom event bus
response = events.put_events(
    Entries=[
        {
            'EventBusName': 'my-event-bus',
            'Source': 'com.mycompany.orders',
            'DetailType': 'OrderShipped',
            'Detail': json.dumps({'order_id': '12345'})
        }
    ]
)
```

## Rules

### Create Rule with Pattern

```python
# Rule to match specific events
events.put_rule(
    Name='order-shipped-rule',
    EventBusName='my-event-bus',
    EventPattern=json.dumps({
        'source': ['com.mycompany.orders'],
        'detail-type': ['OrderShipped'],
        'detail': {
            'status': ['shipped']
        }
    }),
    State='ENABLED',
    Targets=[
        {'Id': 'lambda-target', 'Arn': 'arn:aws:lambda:us-east-1:123456789012:function:order-processor'},
        {'Id': 'sqs-target', 'Arn': 'arn:aws:sqs:us-east-1:123456789012:order-queue'}
    ]
)
```

### Schedule Rules (Cron)

```python
# Run Lambda every day at 9 AM UTC
events.put_rule(
    Name='daily-report-rule',
    ScheduleExpression='cron(0 9 * * ? *)',
    State='ENABLED',
    Targets=[
        {'Id': 'lambda-target', 'Arn': 'arn:aws:lambda:us-east-1:123456789012:function:daily-report'}
    ]
)
```

### Content Filtering Patterns

```json
// Match orders over $1000
{
  "detail": {
    "total": [{"numeric": [">", 1000]}]
  }
}

// Match specific status transitions
{
  "detail": {
    "status": [{"anything-but": "pending"}],
    "previous_status": ["pending"]
  }
}

// Match with OR
{
  "detail-type": ["OrderShipped", "OrderDelivered"]
}
```

## Schema Registry

```python
# Discover schema from an event
events.discover_schema(
    Event='{"source":"com.mycompany.orders","detail-type":"Order","detail":{"order_id":"123"}}'
)

# Bind a schema
events.create_schema(
    Name='order-schema',
    RegistryName='my-registry',
    Content=json.dumps({
        "type": "object",
        "properties": {
            "order_id": {"type": "string"},
            "total": {"type": "number"}
        }
    }),
    Type='JSONSchemaDraft4'
)

# Use schema in CodePipeline, Lambda (auto-generate typed objects)
```

## Event Replay

```bash
# Replay events from archive to target
aws events put-replay \
  --replay-name my-replay \
  --event-bus-arn arn:aws:events:us-east-1:123456789012:event-bus/my-event-bus \
  --source-arn arn:aws:events:us-east-1:123456789012:archive/my-archive \
  --destination '{
    "Arn": "arn:aws:events:us-east-1:123456789012:event-bus/my-event-bus",
    "StartingPosition": "EARLIEST"
  }'
```

## Cross-Account Patterns

```
Account A (Producer)
  │
  └── Event Bus A ──► Rule ──► Event Bus B (Account B)

Account B (Consumer)
  │
  └── Event Bus B (receives from Account A)
      │
      └── Rules for its own targets
```

```python
# Account A: add permission
events.put_permission(
    EventBusName='default',
    Action='events:PutEvents',
    Principal='123456789012'  # Account B's ID
)

# Account B: add event pattern to default bus
events.put_rule(
    Name='cross-account-rule',
    EventPattern=json.dumps({'account': ['123456789012']}),
    Targets=[{'Id': 'my-target', 'Arn': '...'}]
)
```

## Pricing

| Component | Cost |
|-----------|------|
| Custom events published | $1.00/million |
| Schema discovery (per schema) | $0.10/hour |
| Event replay | $0.10/GB |
| Cross-account events | Same as custom events |

## Limits

| Resource | Limit |
|----------|-------|
| Rules per event bus | 100 |
| Event buses per region | 100 |
| Targets per rule | 5 (can request increase) |
| Event size | 256KB |
| Archive retention | Up to 90 days |

## References

- **Homepage:** https://aws.amazon.com/eventbridge/
- **Documentation:** https://docs.aws.amazon.com/eventbridge/
- **Pricing:** https://aws.amazon.com/eventbridge/pricing/

## Nuggets & Gotchas

- **EventBridge rules are evaluated in order — and only the FIRST matching rule's targets receive the event:** Unlike SNS (where ALL subscribers get the message), EventBridge stops after the first matching rule. If you need multiple targets for the same event, use different `detail-type` values or put all targets in a single rule.
- **EventBridge schema registry is OPTIONAL — events work without it, but schemas enable code generation:** Without schema registry, you parse JSON manually. With it, EventBridge can generate strongly-typed classes for Lambda/CodePipeline.
- **EventBridge's `detail-type` is just a string — there's no enforcement of format:** You can put anything in `detail-type`. Use a naming convention like `com.mycompany.orders.OrderShipped` to avoid conflicts.
- **EventBridge replay replays ALL events from the archive that match the filter — not just failed events:** If you archive 100K events and only want to replay the failed ones, you need to filter by event content when replaying or pre-archive selectively.
- **EventBridge cross-account delivery costs $1/million events — it's not free:** Each event delivered across accounts counts as a custom event. For high-volume cross-account scenarios, consider using EventBridge in the producer account with rules that fan out to SQS queues in each consumer account.