---
title: "Amazon API Gateway"
description: "Choose REST, HTTP or WebSocket APIs, configure backend permissions and authentication, and test a complete disposable HTTP endpoint."
tags:
  - cloud/aws/serverless
date: 2026-10-12
---

# Amazon API Gateway

Choose an API type from requirements, not a universal price ranking. REST, HTTP and WebSocket APIs have different authorization, integration, deployment and billing contracts.

## Product boundaries

HTTP APIs support IAM/SigV4, JWT and Lambda authorizers. REST APIs provide their own authorization/features including usage plans and supported caching. [[AWS/serverless/api-gateway/usage-plan|API keys]] identify usage-plan clients; they are not authentication.

REST Regional/private integration timeouts may be increased beyond 29 seconds with documented quota trade-offs. HTTP and WebSocket timeouts have separate contracts. Do not promise gRPC transport without an owning supported integration contract.

REST caches are scoped to the stage and configured method/cache-key parameters; dev/staging/prod do not share one cache automatically. Cache charges are hourly by allocated size, not a universal per-hit/GB tariff. Cache personalized responses only with a safe authorization/key design.

WebSocket Lambda authorization applies at $connect; an existing connection is not reauthorized just because the authorizer changes. Define connection lifetime, identity and backend message authorization separately.

## Small HTTP API lab

Prerequisites: the sandbox function from [[AWS/compute/lambda/README|the Lambda lab]], API creation/deletion and Lambda policy permissions, and an explicit allowance for a **public, unauthenticated nonsensitive greeting endpoint**. Never use this basic lab to expose sensitive data. Set API_LAB_FUNCTION_ARN, API_LAB_REGION and API_LAB_ACCOUNT to the verified sandbox values.

```bash
aws apigatewayv2 create-api \
  --name wiki-http-lab --protocol-type HTTP \
  --target "$API_LAB_FUNCTION_ARN" \
  --region "$API_LAB_REGION"
```

Record ApiId and ApiEndpoint. Quick create supplies the supported integration/default route/default stage; inspect get-routes, get-integrations and get-stages to verify, rather than guessing IDs.

Set API_LAB_ID to the returned ID, then authorize only that API to invoke the function:

```bash
aws lambda add-permission \
  --function-name "$API_LAB_FUNCTION_ARN" \
  --statement-id wiki-http-lab \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$API_LAB_REGION:$API_LAB_ACCOUNT:$API_LAB_ID/*/*" \
  --region "$API_LAB_REGION"
```

Call the returned HTTPS endpoint with curl. Expected: a valid greeting. The API invokes with its event format, so inspect the backend event/response contract rather than reusing direct-invoke assumptions blindly.

Failure exercise: temporarily remove the dedicated invocation permission; expect integration failure while the API endpoint still exists. Restore it and confirm recovery. Configure stage access logging to a dedicated log group before investigating request IDs/status/integration latency; avoid sensitive request bodies.

## Authentication extension and cleanup

Find the actual default RouteId with get-routes and set authorization type AWS_IAM using update-route. Verify an unsigned request is rejected; use an approved SigV4 client with temporary credentials to test the authorized request. Grant the client only the required execute-api ARN.

Delete only the lab API, remove the dedicated Lambda policy statement and delete dedicated access logs. The function belongs to the earlier lab and needs its own cleanup.

## Cost exercise

For an average population of 10,000 concurrent active WebSocket connections maintained over a full 30 days **through reconnects**, connection minutes are 10,000 × 43,200 = 432 million. At an illustrative \$0.25/million that is \$108, plus messages metered in 32-KB increments and other charges. Individual connections cannot last 30 days: API Gateway's maximum connection duration is two hours and its idle timeout is ten minutes. These are [non-adjustable WebSocket limits](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-execution-service-websocket-limits-table.html), not options to purchase longer lifetimes. HTTP/REST requests, data transfer, cache and optional features have their own regional tariffs; JWT use does not create an invented separate HTTP request rate.

## REST, HTTP and WebSocket feature comparison

| Requirement          | REST API                                | HTTP API                                                      | WebSocket API                                                |
| -------------------- | --------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------ |
| Request model        | Supported REST methods/resources        | HTTP routes/integrations                                      | $connect/$disconnect/$default/custom routes                  |
| Client authorization | Supported IAM/Cognito/Lambda mechanisms | IAM/JWT/Lambda mechanisms                                     | Supported $connect authorization plus backend message checks |
| Usage plans/keys     | Supported with method/stage setup       | Not the REST usage-plan model                                 | Product-specific API-key behavior is not user auth           |
| Cache                | Configured stage/method cache           | No equivalent REST cache feature                              | Not an HTTP response-cache model                             |
| Deployment           | Deployment snapshot/stage               | Supported auto-deploy/manual stage                            | Deployment/stage and connection lifecycle                    |
| Private design       | Endpoint/integration options differ     | Private integration is not identical to REST private endpoint | Verify current network/integration contract                  |

CORS is a browser policy, not authorization. Request schema validation, payload transformations, binary content and backend errors vary by product. OpenAPI import must include supported integration/security extensions; a generic schema file does not automatically provision backend permissions.

```text
caller → route/method authentication + optional request controls
                       ↓
             integration + backend permission
                       ↓
                  backend result
                       ↓
        API response/access log/request ID → client
```

## Complete authenticated REST/Lambda setup

This separate paid sandbox reuses the nonsensitive Lambda fixture. Prerequisites: verified profile/Region/account, API creation/deployment permission, Lambda policy permission and a client with narrowly scoped execute-api access. Set API_LAB_REGION/ACCOUNT/FUNCTION_ARN from verified values; record returned IDs at each step.

```bash
aws apigateway create-rest-api --name wiki-rest-lab --region "$API_LAB_REGION"
aws apigateway get-resources --rest-api-id "$API_LAB_REST_ID" \
  --region "$API_LAB_REGION"
aws apigateway create-resource --rest-api-id "$API_LAB_REST_ID" \
  --parent-id "$API_LAB_ROOT_ID" --path-part hello --region "$API_LAB_REGION"
aws apigateway put-method --rest-api-id "$API_LAB_REST_ID" \
  --resource-id "$API_LAB_RESOURCE_ID" --http-method GET \
  --authorization-type AWS_IAM --region "$API_LAB_REGION"
aws apigateway put-integration --rest-api-id "$API_LAB_REST_ID" \
  --resource-id "$API_LAB_RESOURCE_ID" --http-method GET \
  --type AWS_PROXY --integration-http-method POST \
  --uri "arn:aws:apigateway:$API_LAB_REGION:lambda:path/2015-03-31/functions/$API_LAB_FUNCTION_ARN/invocations" \
  --region "$API_LAB_REGION"
aws lambda add-permission --function-name "$API_LAB_FUNCTION_ARN" \
  --statement-id wiki-rest-lab --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$API_LAB_REGION:$API_LAB_ACCOUNT:$API_LAB_REST_ID/*/GET/hello" \
  --region "$API_LAB_REGION"
aws apigateway create-deployment --rest-api-id "$API_LAB_REST_ID" \
  --stage-name lab --region "$API_LAB_REGION"
```

After create-rest-api set API_LAB_REST_ID; identify the resource with path / as API_LAB_ROOT_ID, then save the created hello resource ID. Lambda integration's internal HTTP method is POST even though the client method is GET.

Use a supported SigV4 client against https://REST_ID.execute-api.REGION.amazonaws.com/lab/hello. Expected: greeting with valid IAM permission; unsigned/excluded identity is denied. Remove the dedicated Lambda policy statement to produce an integration failure, then restore it. This distinguishes client auth from backend auth.

Delete the dedicated REST API and its Lambda statement/logs after tests; deleting the API does not delete the reused function. Other partitions require their actual ARN/DNS formats, not a blind arn:aws copy.

## Authorizers and invocation contracts

For REST Cognito/Lambda and HTTP JWT/Lambda, configure actual issuer/audience/scopes/token source and caching according to the product. Use [[AWS/security/cognito|the complete PKCE/scope/tenant lesson]] for customer identity. An undefined validate(token) helper is not secure JWT validation.

Lambda authorizer payload version and response format differ: REST IAM policy/principal response versus supported HTTP simple/policy forms. Cached authorizer results can span routes according to identity-source/cache key; review tenant/path authorization and revocation expectations. Verify signatures/issuer/expiry/client/scopes through a maintained validator; merely decoding a JWT is not access control.

## Throttling, caching and import/export operations

HTTP throttling belongs to supported stage route/default settings, not a nonexistent update-route --default-route-settings flag:

```bash
aws apigatewayv2 update-stage --api-id "$API_LAB_ID" --stage-name '$default' \
  --default-route-settings '{"ThrottlingBurstLimit":10,"ThrottlingRateLimit":5}' \
  --region "$API_LAB_REGION"
```

REST usage plans require deployed stage association, key ID and apiKeyRequired; see [[AWS/serverless/api-gateway/usage-plan|the complete plan workflow]]. All throttles/quotas are best effort, not hard cost caps.

REST cache allocation/method settings use the documented update-stage patch paths and add hourly capacity charges. Configure cache keys and authorization isolation; never enable a shared personalized-response cache simply because the client is authenticated. Test cache hit/miss, invalidation and per-stage isolation with synthetic data.

For OpenAPI import, use import-rest-api with a protected supported file and fail-on-warnings. Export from the deployed stage using get-export; review backend integration/authorizer extensions, secrets and drift. Exported descriptions are not proof all referenced roles/backends exist.

## WebSocket connection and callback walkthrough

```text
$connect auth → connection ID → permitted message routes → backend
                         ↑                             ↓
                   $disconnect/expiry ← Management API callback
```

Create a dedicated WebSocket API with route-selection expression $request.body.action. Add an actual integration for each intended route and set its target integrations/INTEGRATION_ID; merely creating the route does not attach Lambda. Grant the backend invocation policy and deploy a stage.

Persist connection ownership with TTL/lifecycle handling; $disconnect is not a universal guaranteed cleanup signal. An authorized backend uses the **apigatewaymanagementapi** client at the deployed callback endpoint with execute-api:ManageConnections scope to send bytes to an active connection. Handle GoneException/stale connections, retry/backpressure and per-message metering.

Plan bounded reconnects before the two-hour limit, and application activity/heartbeat within the ten-minute idle window when a continuously connected client is needed. Reconnection creates a new connection ID and repeats `$connect` authentication; replace stale ownership records rather than treating the old ID as a permanent user identifier. In the exercise, reconnect one client, confirm its new ID, and attempt a callback to the old ID: handle `GoneException` without deleting the new connection record. Reauthorize tenant/resource operations and recover missed messages through an application-level cursor or durable store when required; WebSocket reconnection alone does not replay them.

Authentication at $connect does not authorize every later message/resource. Test a second identity trying another connection/tenant's action and enforce backend ownership. Close lab clients, remove connection records/routes/integrations/API and dedicated roles/logs after acceptance.

## Operational troubleshooting

| Symptom              | Distinguish                                                      | Evidence                                                |
| -------------------- | ---------------------------------------------------------------- | ------------------------------------------------------- |
| 401/403              | Missing/invalid identity, scope/IAM/resource policy or usage key | Product-specific access logs and authorizer outcome     |
| 429                  | Route/stage/account/downstream pressure                          | Throttle metrics, bounded retries and quota scope       |
| 5xx                  | Integration URI/permission/backend exception/timeout             | Request ID, integration status/latency and backend logs |
| Browser-only failure | CORS/preflight versus actual API denial                          | OPTIONS/headers plus authorized direct client           |
| Wrong cached data    | Cache keys/stage/auth isolation                                  | Synthetic two-client hit/miss test                      |

Log request/status/integration metadata, not credentials or token bodies. Preserve error correlation and deployed revision. A successful test-invoke/control-plane create does not prove every end-user authorization path.

References: [REST Lambda integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html), [REST deployment](https://docs.aws.amazon.com/cli/latest/reference/apigateway/create-deployment.html), [HTTP stage settings](https://docs.aws.amazon.com/cli/latest/reference/apigatewayv2/update-stage.html), [OpenAPI](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-import-api.html), [WebSocket integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-websocket-api-integration-requests.html), [callbacks](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-how-to-call-websocket-api-connections.html).

## Across the wiki

- [[Architecture/solution-architecture-concepts/api-design/README|API Design]] — API design and gateways (Architecture)
- [[Architecture/solution-architecture-concepts/performance/rate-limiting|Rate Limiting Algorithms, Distributed Architecture & HTTP 429]] — API design and gateways (Architecture)
- [[Architecture/solution-architecture-concepts/software-engineering-concepts/api-error-codes|API Error Codes, HTTP Status Standards & RFC 7807 Problem Details]] — API design and gateways (Architecture)
- [[Architecture/solution-architecture-concepts/protocols/README|Protocols]] — API design and gateways (Architecture)

## References

- [HTTP quick create](https://docs.aws.amazon.com/cli/latest/reference/apigatewayv2/create-api.html).
- [HTTP IAM authorization](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-access-control-iam.html).
- [Lambda permissions](https://docs.aws.amazon.com/lambda/latest/dg/services-apigateway.html).
- [REST caching](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-caching.html).
- [REST timeout increase](https://aws.amazon.com/about-aws/whats-new/2024/06/amazon-api-gateway-integration-timeout-limit-29-seconds/).
- [WebSocket authorization](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-websocket-api-lambda-auth.html).
- [Pricing](https://aws.amazon.com/api-gateway/pricing/).
