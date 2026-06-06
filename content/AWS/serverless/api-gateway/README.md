---
title: Amazon API Gateway
description: Amazon API Gateway — REST, HTTP, and WebSocket APIs. Endpoints, stages, methods, authorizers (Cognito/Lambda), rate limiting, caching, OpenAPI import, and cost.
tags:
  - aws
  - serverless
  - api-gateway
  - rest-api
  - http-api
  - websocket
---

# Amazon API Gateway

API Gateway exposes Lambda, HTTP backends, and other AWS services as REST or HTTP APIs. It handles authentication, rate limiting, caching, and monitoring.

## REST vs HTTP vs WebSocket

| Feature | REST API | HTTP API | WebSocket API |
|---------|----------|----------|---------------|
| Protocols | REST, OData | REST, gRPC | WebSocket |
| Auth | IAM, Cognito, Lambda | JWT, Lambda | Lambda |
| Rate limiting | Usage plans, API keys | Throttling per route | Connection limits |
| Caching | Yes | No | No |
| Cost | $3.50/million | $0.50-1.00/million | $1.00/million + $0.25/million connection-minutes |
| Use case | Full-featured API | Lightweight, modern | Real-time, chat, dashboards |

## REST API

### Create API

```bash
# Create REST API
aws apigateway create-rest-api \
  --name my-api \
  --description "My REST API" \
  --endpoint-types REGIONAL

# Get API ID
API_ID=$(aws apigateway get-rest-apis --query 'items[0].id' --output text)
```

### Resources and Methods

```bash
# Create resource
RESOURCE_ID=$(aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $(aws apigateway get-resources --rest-api-id $API_ID --query 'items[0].id' --output text) \
  --path-part orders \
  --query 'id' --output text)

# Create GET method
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --authorization-type NONE

# Create Lambda integration
aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:my-function/invocations

# Create POST method
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method POST \
  --authorization-type COGNITO_USER_POOLS \
  --authorizer-id authorizer-xxxxx

# Deploy API
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name v1 \
  --description "Production v1"

# URL: https://{api-id}.execute-api.us-east-1.amazonaws.com/v1/orders
```

## HTTP API

```bash
# Create HTTP API
aws apigatewayv2 create-api \
  --name my-http-api \
  --protocol-type HTTP

# Create route
aws apigatewayv2 create-route \
  --api-id $API_ID \
  --route-key "GET /orders"

# Integrate with Lambda
aws apigatewayv2 create-integration \
  --api-id $API_ID \
  --integration-type AWS_PROXY \
  --integration-uri arn:aws:lambda:us-east-1:123456789012:function:my-function \
  --payload-format-version 2.0

# Create stage
aws apigatewayv2 create-stage \
  --api-id $API_ID \
  --stage-name v1 \
  --auto-deploy
```

## Authorizers

### Cognito Authorizer (REST API)

```bash
aws apigateway create-authorizer \
  --rest-api-id $API_ID \
  --name CognitoAuthorizer \
  --type COGNITO_USER_POOLS \
  --provider-arns arn:aws:cognito-idp:us-east-1:123456789012:userpool/us-east-1_xxxxx
```

### Lambda Authorizer (JWT)

```python
def lambda_authorizer(event, context):
    token = event['headers']['Authorization']
    
    # Validate JWT
    if validate(token):
        return {
            'principalId': 'user-123',
            'policyDocument': {
                'Version': '2012-10-17',
                'Statement': [{
                    'Action': 'execute-api:Invoke',
                    'Effect': 'Allow',
                    'Resource': event['methodArn']
                }]
            }
        }
    else:
        return {'principalId': 'unauthorized', 'policyDocument': {'Version': '2012-10-17', 'Statement': [{'Action': 'execute-api:Invoke', 'Effect': 'Deny', 'Resource': '*'}]}}
```

## Rate Limiting

### REST API (Usage Plans)

```bash
# Create usage plan
aws apigateway create-usage-plan \
  --name production \
  --description "Production usage plan" \
  --quota '{ "limit": 1000000, "period": "MONTH" }' \
  --throttle '{ "burstLimit": 5000, "rateLimit": 1000 }'

# Create API key
API_KEY=$(aws apigateway create-api-key \
  --name "production-key" \
  --enabled \
  --query 'value' --output text)

# Associate with usage plan
aws apigateway create-usage-plan-key \
  --usage-plan-id plan-xxxxx \
  --key-id $API_KEY \
  --key-type API_KEY

# Client includes key in header: x-api-key: your-key
```

### HTTP API (Per-route throttling)

```bash
# Update route to set throttling
aws apigatewayv2 update-route \
  --api-id $API_ID \
  --route-id route-xxxxx \
  --route-key "GET /orders" \
  --default-route-settings '{
    "ThrottlingBurstLimit": 1000,
    "ThrottlingRateLimit": 500
  }'
```

## Caching (REST API)

```bash
# Enable caching on method
aws apigateway put-method-settings \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --stage-name v1 \
  --settings '{
    "CachingEnabled": true,
    "CacheTtlInSeconds": 300,
    "CacheDataEncrypted": true,
    "RequireAuthorizationForCacheControl": true,
    "UnauthorizedCacheControlHeaderStrategy": "REPLACE_WITH_403"
  }'
```

## OpenAPI Import

```bash
# Import from OpenAPI spec
aws apigateway import-rest-api \
  --body file://openapi-spec.json \
  --fail-on-warnings

# Export to OpenAPI
aws apigateway get-export \
  --rest-api-id $API_ID \
  --stage-name v1 \
  --export-type swagger openapi-spec.json
```

## WebSocket API

```bash
# Create WebSocket API
aws apigatewayv2 create-api \
  --name my-websocket \
  --protocol-type WEBSOCKET \
  --route-selection-expression '$request.body.action'

# Create routes
aws apigatewayv2 create-route \
  --api-id $API_ID \
  --route-key '$connect' \
  --authorization-type NONE

aws apigatewayv2 create-route \
  --api-id $API_ID \
  --route-key '$disconnect'

aws apigatewayv2 create-route \
  --api-id $API_ID \
  --route-key 'sendMessage'

# Integrate with Lambda
aws apigatewayv2 create-integration \
  --api-id $API_ID \
  --integration-type AWS_PROXY \
  --integration-uri arn:aws:lambda:us-east-1:123456789012:function:websocket-handler
```

## Pricing

| API Type | Cost |
|----------|------|
| REST API | $3.50/million API calls |
| HTTP API | $1.00/million (with JWT auth), $0.50/million (without) |
| WebSocket | $1.00/million messages + $0.25/million connection-minutes |
| REST caching | $0.020/hour per GB |

## References

- **Homepage:** https://aws.amazon.com/api-gateway/
- **Documentation:** https://docs.aws.amazon.com/apigateway/
- **Pricing:** https://aws.amazon.com/api-gateway/pricing/

## Nuggets & Gotchas

- **REST API and HTTP API are different products — you CANNOT convert a REST API to HTTP API:** They have different features, pricing, and architectures. If you start with REST and later want HTTP pricing, you must recreate the API.
- **API Gateway's 29-second timeout applies to Lambda proxy integrations — for longer operations, use async invocation:** If your Lambda takes > 29 seconds, API Gateway returns a 504. Use SQS to queue long tasks, or use HTTP APIs with Lambda async invocation.
- **HTTP API doesn't support API keys or usage plans — if you need client identification, use REST API or Cognito:** HTTP APIs are designed for service-to-service communication. They support JWT/Cognito but not API key authentication.
- **API Gateway caching is per stage — if you have multiple environments (dev/staging/prod) sharing the same API, caching affects all:** Cache is keyed by route+query params, not by stage. If your API returns different data per user, enable authorization for cache control.
- **WebSocket connections stay open — each connection costs money even when idle:** $0.25/million connection-minutes means 10K always-open connections cost $180/month. Implement connection timeout/disconnect logic to avoid idle connection costs.