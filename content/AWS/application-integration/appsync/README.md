---
title: AWS AppSync
description: AWS AppSync — managed GraphQL API with real-time subscriptions. Schema, resolvers (VTL/Lambda), DynamoDB integration, Cognito auth, and subscription filtering.
tags:
  - aws
  - application-integration
  - appsync
  - graphql
---

# AWS AppSync

AppSync is a managed GraphQL service. You define a schema, attach resolvers (to DynamoDB, Lambda, etc.), and AppSync handles the API, real-time subscriptions, and authentication. Clients can query, mutate, and subscribe to data changes.

## Core Concepts

```
Client (Web/Mobile)
  │
  ├──► GraphQL Query ──────────────► AppSync API
  │                                    │
  ├──► GraphQL Mutation ───────────► │ Resolvers
  │                                    │   │
  └──► GraphQL Subscription ◄─────────│   ▼
                                      │ DynamoDB / Lambda / HTTP
                                      ▼
                                  Real-time (WebSocket)
```

## Creating an API

```bash
# Create AppSync API
aws appsync create-graphql-api \
  --name my-api \
  --authentication-type API_KEY

# Get API ID and endpoint
aws appsync get-graphql-api --api-id xxxxxxxx

# Create API key (if using API_KEY auth)
aws appsync create-api-key --api-id xxxxxxxx
```

## Schema Definition

```graphql
type Order {
  orderId: ID!
  customerId: ID!
  total: Float!
  status: OrderStatus!
  createdAt: AWSDateTime!
}

enum OrderStatus {
  PENDING
  PROCESSING
  SHIPPED
  DELIVERED
}

type Query {
  getOrder(orderId: ID!): Order
  listOrders(customerId: ID!, limit: Int, nextToken: String): OrderConnection
}

type Mutation {
  createOrder(customerId: ID!, total: Float!): Order
  updateOrderStatus(orderId: ID!, status: OrderStatus!): Order
}

type Subscription {
  onOrderStatusChanged(orderId: ID): Order
}

type OrderConnection {
  orders: [Order!]!
  nextToken: String
}
```

## DynamoDB Resolvers

### Create Data Source

```bash
# Create DynamoDB table data source
aws appsync create-data-source \
  --api-id xxxxxxxx \
  --name orders-table \
  --type AMAZON_DYNAMODB \
  --dynamodb-config '{
    "tableName": "Orders",
    "region": "us-east-1"
  }' \
  --service-role-arn arn:aws:iam::123456789012:role/appsync-role
```

### Resolver (VTL Template)

**Query - getOrder:**
```vtl
## request
{
  "version": "2017-02-28",
  "operation": "GetItem",
  "key": {
    "orderId": {"S": "$context.arguments.orderId"}
  }
}

## response
#if($ctx.result)
  $util.toJson($ctx.result)
#else
  $util.error("Order not found", "NotFound")
#end
```

**Query - listOrders (Paginated):**
```vtl
## request
{
  "version": "2017-02-28",
  "operation": "Query",
  "query": {
    "expression": "customerId = :customerId",
    "expressionValues": {
      ":customerId": {"S": "$context.arguments.customerId"}
    }
  },
  "limit": #if($context.arguments.limit) $context.arguments.limit #else 20 #end,
  "nextToken": #if($context.arguments.nextToken) "$context.arguments.nextToken" #else null #end
}

## response
{
  "orders": $util.toJson($ctx.result.items),
  "nextToken": #if($ctx.result.nextToken) "$ctx.result.nextToken" #else null #end
}
```

**Mutation - createOrder (with auto-ID and timestamp):**
```vtl
## request
#set($orderId = $util.autoId())
#set($createdAt = $util.time.nowISO8601())
{
  "version": "2017-02-28",
  "operation": "PutItem",
  "key": {"orderId": {"S": "$orderId"}},
  "attributeValues": {
    "orderId": {"S": "$orderId"},
    "customerId": {"S": "$context.arguments.customerId"},
    "total": {"N": "$context.arguments.total"},
    "status": {"S": "PENDING"},
    "createdAt": {"S": "$createdAt"}
  }
}

## response
$util.toJson($ctx.result)
```

## Lambda Resolvers

```python
def handler(event, context):
    # event['arguments'] = query/mutation arguments
    # event['identity'] = caller info (Cognito, API key, etc.)
    
    if event['info']['fieldName'] == 'recommendProducts':
        customer_id = event['arguments']['customerId']
        return get_recommendations(customer_id)
    
    return None
```

## Authentication

### Cognito User Pools

```bash
aws appsync create-graphql-api \
  --name my-api \
  --authentication-type AMAZON_COGNITO_USER_POOLS \
  --user-pool-config '{
    "userPoolId": "us-east-1_xxxxx",
    "defaultAction": "ALLOW",
    "awsRegion": "us-east-1"
  }'
```

### API Key (dev/test)

```bash
aws appsync create-api-key --api-id xxxxxxxx
```

## Real-time Subscriptions

```graphql
# Client subscribes to order status changes
subscription OnOrderStatusChanged($orderId: ID) {
  onOrderStatusChanged(orderId: $orderId) {
    orderId
    status
    updatedAt
  }
}
```

### Subscription Filtering

```vtl
## In the mutation resolver (publish to subscriptions)
{
  "version": "2017-02-28",
  "payload": $util.toJson($ctx.result)
}
```

Subscriptions filter by the resolved payload. Use `@aws_subscribe` directive:

```graphql
type Mutation {
  updateOrderStatus(orderId: ID!, status: OrderStatus!): Order
    @aws_subscribe(mutations: ["updateOrderStatus"])
}
```

## Pricing

| Component | Cost |
|-----------|------|
| Queries | $0.004/million reads |
| Mutations | $0.008/million writes |
| Real-time subscriptions | $0.008/million minutes |
| Data transfer | Standard EC2 rates |

## Limits

| Resource | Limit |
|----------|-------|
| API per region | 25 |
| Schema size | 600KB |
| Resolver timeout | 30 seconds |
| Lambda resolver memory | 10240MB |

## References

- **Homepage:** https://aws.amazon.com/appsync/
- **Documentation:** https://docs.aws.amazon.com/appsync/
- **Pricing:** https://aws.amazon.com/appsync/pricing/

## Nuggets & Gotchas

- **AppSync resolvers timeout after 30 seconds — if your Lambda resolver takes longer, it fails:** For long-running operations (batch processing, ML inference), either use async patterns (start job, poll for result) or increase Lambda timeout and AppSync resolver timeout together.
- **AppSync VTL templates are DIFFERENT from Velocity templates — don't assume syntax compatibility:** AppSync uses VTL (Velocity Template Language) for resolvers. The syntax `$util.toJson()` and `$context.arguments` are AppSync-specific. VTL debugging is painful — test resolvers in the console first.
- **AppSync subscriptions use WebSockets — they stay open permanently, consuming connection slots:** Each subscription = 1 persistent WebSocket connection. On mobile, if users have poor connectivity, connections can pile up. Set CloudWatch alarms for connection count.
- **AppSync API Keys expire after 365 days by default — if they expire, API calls fail silently:** If you're using API_KEY auth and your app breaks, check if the key expired. Use Cognito User Pools or IAM auth for production.
- **AppSync doesn't support real-time filtering on the server — clients receive all subscription events and filter client-side:** If you need server-side filtering (only notify relevant users), you must implement filtering in your Lambda resolver before returning the payload.