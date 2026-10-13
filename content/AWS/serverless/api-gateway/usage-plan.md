---
title: "API usage plans and keys"
description: "Identify REST API consumers and apply best-effort quotas without mistaking API keys for authorization or hard spending caps."
tags:
  - cloud/aws/serverless/api-gateway
date: 2026-10-12
---

# API usage plans and keys

REST API usage plans associate API stages and API keys with throttling/quota settings. They support usage tracking and service tiers, but **API keys are not authentication or authorization**, and limits are **best effort**, not hard spending caps.

## Separate the controls

Authenticate and authorize with a supported IAM/authorizer mechanism. A usage key identifies a consumer for plan accounting. Stage/method/account throttle constraints can also apply. A key granting usage access to multiple associated stages must not bypass application tenant authorization.

Rate/burst controls use token-bucket behavior; quotas measure requests over an interval. Requests can exceed configured settings. Use workload-side enforcement, budgets, anomaly alerts and abuse controls where business/cost limits matter.

## Sandbox verification

Prerequisites: a disposable REST API, deployed stage, one API-key-required method, authentication configured independently and scoped permissions.

1. Create a dedicated plan with a small test quota/rate and associate the lab stage.
2. Create/associate a test key, then wait for configuration propagation.
3. Invoke without the key: expect rejection for the key-required method.
4. Invoke with the key but without valid authentication: expect authorization failure.
5. Invoke with both: expect a successful sandbox response.
6. Send a bounded burst and inspect throttles/usage. Do not assume an exact count of accepted requests or use this to prove a hard billing cap.

Never log or publish the key. Rotating a key does not revoke an independently issued identity token.

## Cleanup and next steps

Remove the dedicated key/plan/stage/API and access logs after preserving test evidence. Remove only lab backend permissions. Read [[AWS/serverless/api-gateway/README|the API Gateway lesson]] for product selection, backend permissions, access logs and pricing dimensions.

## Plan/key/stage architecture and control comparison

```text
authenticated consumer + usage key → API-key-required REST method
                                          ↓
                              associated stage + usage plan
                                          ↓
                       method/stage/account/service throttles
```

| Control               | Counts/limits                      | Not a substitute for                          |
| --------------------- | ---------------------------------- | --------------------------------------------- |
| Rate/burst            | Best-effort token-bucket admission | Authentication or a guaranteed exact RPS wall |
| Usage quota           | Requests over a supported period   | Hard invoice cap or tenant authorization      |
| Stage/method throttle | Deployed API path behavior         | Per-customer pricing contract by itself       |
| API key               | Usage-plan client identity         | Cryptographic user authentication             |
| IAM/authorizer        | Supported caller access            | Usage accounting or backend ownership checks  |

Usage keys can be associated with multiple stages/plans under documented restrictions. Do not use an API key's display name or raw value as the create-usage-plan-key key-id; use the returned **ID**.

## Complete association workflow

Prerequisites: an existing disposable REST API/stage and method configured with independent authentication and apiKeyRequired=true. Use returned IDs and scoped permissions; never print/publish the key value.

```bash
aws apigateway create-usage-plan --name wiki-lab-plan \
  --api-stages apiId=REST_API_ID,stage=lab \
  --throttle burstLimit=10,rateLimit=5 \
  --quota limit=100,period=DAY
aws apigateway create-api-key --name wiki-lab-consumer --enabled \
  --query '{id:id,name:name}' --output json
aws apigateway create-usage-plan-key --usage-plan-id PLAN_ID \
  --key-id KEY_ID --key-type API_KEY
aws apigateway get-usage --usage-plan-id PLAN_ID \
  --start-date 2026-10-12 --end-date 2026-10-13
```

Retrieve the key through an authorized secure workflow only for the client test and send it in x-api-key. Test missing key, valid key without identity auth and both valid. Wait for supported propagation rather than assuming immediate association.

Updating apiKeyRequired on a REST method needs the proper method patch/deployment workflow; creating the plan alone does not enforce a key requirement. Existing deployments remain their snapshots until redeployed as required.

## Throttle diagnosis and cleanup

Inspect 429/access-log/request-ID evidence across usage-plan, method/stage, account and service quotas. A bounded burst may temporarily exceed configured rate/quota; no exact accepted-count prediction proves a hard cap. Use client backoff/jitter and business-side enforcement when a strict entitlement is required.

Delete dedicated plan associations/key/plan after the exercise, then only the owned API stage/backend/logs. Rotating/deleting a usage key does not revoke a separate JWT or repair a compromised backend credential.

References: [CreateUsagePlan](https://docs.aws.amazon.com/cli/latest/reference/apigateway/create-usage-plan.html), [usage-plan key](https://docs.aws.amazon.com/cli/latest/reference/apigateway/create-usage-plan-key.html), [method update](https://docs.aws.amazon.com/cli/latest/reference/apigateway/update-method.html).

## References

- [Usage plans and limitations](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-api-usage-plans.html).
- [API throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html).
