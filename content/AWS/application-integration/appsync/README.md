---
title: AWS AppSync
description: AWS AppSync — managed GraphQL API with real-time subscriptions. Schema, resolvers (VTL/Lambda), DynamoDB integration, Cognito auth, and subscription filtering.
tags:
  - aws/application-integration
date: 2026-10-12
---

# AWS AppSync

Prerequisites: [[AWS/security/iam/README|scoped IAM roles]] and [[AWS/monitoring/README|delivery/processing observability]].

AppSync provides managed GraphQL APIs and separate Event APIs for realtime messaging. A schema is not an authorization model: enforce identity and tenant boundaries at resolvers and data access.

## GraphQL model

Resolvers connect schema fields to data sources (or NONE for local transformations). AppSync JavaScript and VTL are separate runtimes; choose one deliberately. Authentication can use IAM, Cognito user pools, OIDC, Lambda authorizers or API keys under their documented compatibility rules. API keys suit controlled demos, not user authorization.

Subscriptions are coupled to mutations and selection sets: fields absent from the mutation result cannot magically appear at subscribers. Enhanced subscription filters execute server-side and can use identity/context; when enhanced filtering is defined it takes precedence over basic filtering as documented. A WebSocket can carry multiple subscriptions; do not assume one connection per field.

## Complete console sandbox

Prerequisites: a sandbox role able to create/delete AppSync APIs, schemas, data sources and resolvers. No database, Lambda or data-source service role is required for a NONE data source.

1. Create a GraphQL API named wiki-lab with API-key authentication, explicitly set a short expiry and retain its endpoint/key securely.
2. Install this schema:

```graphql
type Query {
  echo(message: String!): String!
}
schema {
  query: Query
}
```

3. Create a data source named Local of type NONE. Attach a UNIT resolver to Query.echo using runtime APPSYNC_JS version 1.0.0 and this complete code:

```javascript
export function request(ctx) {
  return { payload: ctx.args.message };
}
export function response(ctx) {
  return ctx.result;
}
```

4. In the console query editor, run `query { echo(message: "hello") }` with the configured API key. Expected data.echo is hello. Invoke without a key in an unauthenticated test client and expect authorization failure; the console's logged-in context is not sufficient to test anonymous access.
5. Delete the API and verify its key/endpoint no longer authorize requests. No external data source was provisioned, so there is no hidden database cleanup.

Before production replace the demo authentication with identity-aware authorization, test unauthorized tenant/field access, and add backend-role policies, structured errors/logging, resolver limits and tracing. API-key lifetimes and request timeouts are quota/contract-specific, not universal adjustable promises.

## Cost model

GraphQL query/data-modification operations currently start at \$4 per million under the owning rate table, not \$0.004 or separate invented mutation tariffs. At that illustrative rate, one million queries plus one million mutations cost \$8 before discounts/allowances. Realtime updates, connection-minutes, caching, data transfer and Event API operations have different dimensions. Confirm Region, date and operation type before projecting costs.

## Schema, resolver and authorization architecture

```text
client query/mutation → authentication → field resolver
                                         ├─ NONE transformation
                                         ├─ DynamoDB + narrow data-source role
                                         ├─ Lambda + invoke permission
                                         └─ supported HTTP/other data source
mutation result → selected subscription fields → authorized subscribers
```

| Layer               | Defines                              | Does not automatically provide               |
| ------------------- | ------------------------------------ | -------------------------------------------- |
| Schema              | Types, operations and relationships  | Tenant authorization or database indexes     |
| Resolver            | Request/response and business checks | Infinite pagination or implicit transactions |
| Data source role    | Supported backend AWS access         | Permission for every end-user object         |
| Authentication      | Caller identity/token validity       | Field/resource ownership                     |
| Subscription filter | Which matching results are delivered | Permission to mutate the source data         |

## Order schema and subscription coupling

This complete teaching schema extends the NONE demo concept; it requires real resolvers before it works as a persistence API. All values are synthetic.

```graphql
type Order {
  orderId: ID!
  customerId: ID!
  status: String!
  updatedAt: AWSDateTime!
}
type OrderConnection {
  orders: [Order!]!
  nextToken: String
}
type Query {
  getOrder(orderId: ID!): Order
  listOrders(customerId: ID!, limit: Int, nextToken: String): OrderConnection
}
type Mutation {
  updateOrderStatus(orderId: ID!, status: String!): Order
}
type Subscription {
  onOrderStatusChanged(orderId: ID!): Order
    @aws_subscribe(mutations: ["updateOrderStatus"])
}
schema {
  query: Query
  mutation: Mutation
  subscription: Subscription
}
```

The directive belongs to the **subscription** field, not the mutation field. The mutation's selection set must supply fields needed by subscribers; request orderId/customerId/status/updatedAt and test missing/null behavior. Basic argument filtering and enhanced subscription-resolver filtering have different precedence. Authorize subscription registration and mutation separately.

## DynamoDB data source and GetItem resolver

Prerequisites: a disposable table keyed by orderId, scoped AppSync role trusting appsync.amazonaws.com and only required table actions, API ID and current JS runtime. A data-source name uses supported identifier characters; use Orders rather than orders-table.

```bash
aws appsync create-data-source --api-id API_ID --name Orders \
  --type AMAZON_DYNAMODB --service-role-arn APPSYNC_ROLE_ARN \
  --dynamodb-config '{"tableName":"WikiOrders","awsRegion":"us-east-1"}'
```

Attach this APPSYNC_JS resolver to Query.getOrder (replace account/Region/table setup first):

```javascript
import { util } from "@aws-appsync/utils";

export function request(ctx) {
  return {
    operation: "GetItem",
    key: util.dynamodb.toMapValues({ orderId: ctx.args.orderId }),
  };
}
export function response(ctx) {
  if (ctx.error) {
    util.error(ctx.error.message, ctx.error.type);
  }
  return ctx.result;
}
```

This retrieves synthetic data only; add authoritative identity/ownership checks before serving customer records. A GetItem role on the table does not give all API callers ownership.

listOrders by customerId needs a suitable table key or GSI and explicit IndexName/query expression. Pagination passes AppSync's returned nextToken as an opaque continuation token; it is not a user-controlled DynamoDB key. A customerId query cannot target an orderId-only table without the required access path.

## Lambda/VTL and realtime diagnostics

For Lambda, define the resolver payload explicitly: an event's arguments/identity/info shape is the result of the integration configuration, not a universal Lambda trigger contract. A complete handler needs its referenced helpers and an IAM permission to invoke the exact function. Keep backend failures distinct from GraphQL nullability errors.

VTL request and response templates are separate artifacts; do not paste both into one request file. AppSync JavaScript is not a Node runtime with arbitrary packages/filesystem/network calls.

Test API authentication, field auth, own/other-tenant data, mutation result selection and subscriber filters. Inspect resolver logs with sensitive field redaction, latency/error metrics, data-source throttles and active connection behavior. Remove subscriptions before deleting the disposable API/data source/table, and delete only the dedicated backend role/functions. Realtime bills update fan-out and connection-minutes separately from GraphQL operations.

References: [DynamoDB JS resolvers](https://docs.aws.amazon.com/appsync/latest/devguide/js-resolver-reference-dynamodb.html), [data-source contract](https://docs.aws.amazon.com/cli/latest/reference/appsync/create-data-source.html), [subscription coupling](https://docs.aws.amazon.com/appsync/latest/devguide/aws-appsync-real-time-data.html), [Lambda JS integration](https://docs.aws.amazon.com/appsync/latest/devguide/resolver-reference-lambda-js.html).

## References

- [AppSync JavaScript NONE data source](https://docs.aws.amazon.com/appsync/latest/devguide/resolver-reference-none-js.html)
- [Authorization modes](https://docs.aws.amazon.com/appsync/latest/devguide/security-authz.html)
- [Enhanced filtering](https://docs.aws.amazon.com/appsync/latest/devguide/aws-appsync-real-time-enhanced-filtering.html)
- [GraphQL subscription behavior](https://docs.aws.amazon.com/appsync/latest/devguide/aws-appsync-real-time-data.html)
- [Pricing](https://aws.amazon.com/appsync/pricing/)

## Across the wiki

- [[Architecture/solution-architecture-concepts/api-design/README|API Design]]
- [[Architecture/solution-architecture-concepts/performance/rate-limiting|Rate Limiting Algorithms, Distributed Architecture & HTTP 429]]
- [[Architecture/solution-architecture-concepts/software-engineering-concepts/api-error-codes|API Error Codes, HTTP Status Standards & RFC 7807 Problem Details]]
- [[Architecture/solution-architecture-concepts/protocols/README|Protocols]]
