---
title: Amazon Cognito application identity
description: Distinguish user-pool tokens from identity-pool AWS credentials and test a PKCE-protected application/API flow.
tags:
  - cloud/aws/security/identity
date: 2026-10-12
---

# Amazon Cognito application identity

Cognito serves application users. [[AWS/security/iam/identity-center|Identity Center]] serves workforce access; [[AWS/security/iam/policy-evaluation|IAM]] authorizes AWS resource actions. These are different boundaries.

## User pools and identity pools

A user pool authenticates supported users/providers and issues application tokens. An identity pool can exchange supported identity tokens for temporary, role-scoped AWS credentials. Either component can be used without the other; an identity pool is unnecessary when a backend accesses AWS using its own role.

Treat ID tokens as identity claims and access tokens as API authorization inputs. Verify signature/key, issuer, expiry, intended client/audience and required scopes with a maintained validator; base64-decoding a JWT is not verification. A valid token still needs application tenant/resource authorization.

Public browser/mobile clients cannot safely hold a client secret. Use authorization code with PKCE and exact approved callbacks. Protect state/nonce and token storage through a supported client/library. Do not embed machine-to-machine client credentials in browser code.

## Sandbox sign-in/API exercise

Prerequisites: approved sandbox account/Region, a nonsensitive app with a controlled callback, a supported OAuth client/library and the disposable [[AWS/serverless/api-gateway/README|HTTP API/backend]]. Features, active users, messaging and dependencies can incur charges.

1. Create a dedicated user pool, review sign-up/MFA/recovery and abuse settings, and add only a test user.
2. Create a resource server with a custom read scope (for example, identifier `wiki-api` and scope `read`, producing `wiki-api/read`). Create a public app client without an embedded secret, with authorization-code grant and PKCE. Register exact callback/logout URLs and allow only the required scopes, including that custom scope.
3. Configure managed login/domain and request the permitted custom scope during the PKCE authorization flow. Sign in using the maintained client and verify the access token contains the scope. Never paste tokens into shared logs.
4. Configure the HTTP API JWT authorizer with the actual pool issuer and expected client/audience; require the same custom scope (`wiki-api/read` in this example) on the route. This is a separate extension from the IAM-authorized example.
5. Invoke with a valid access token: expect the approved sandbox response.
6. Try no token, an expired token, a token lacking the required scope and a token from another pool/client: expect rejection. The greeting backend proves authentication/scope gating only; it does not implement tenant/resource authorization.
7. End/revoke test sessions through supported workflows. Delete dedicated user/client/domain/pool, authorizer/API/backend and logs according to ownership. Deleting browser storage alone does not revoke every token.

Record allowed/denied cases and issuer/client/scope configuration, not token values.

### Separate tenant-isolation extension

Before expecting cross-tenant denial, implement a backend resource-ownership check and create **two test users and two synthetic owner-bound resources**. Derive the authenticated subject from the API's verified authorizer claims, not a client-supplied owner field; restrict the caller so it cannot bypass the API and invoke the function directly. Test own-resource success and other-user-resource denial for both users. The original greeting handler cannot pass this test without additional application logic. Remove both users/resources during extension cleanup.

## Identity-pool extension

Only add direct AWS credentials when the client must call AWS. Scope authenticated-role trust and resource permissions to the intended identity pool/identity; keep unauthenticated access disabled unless explicitly required and tested.

Prove one user's credentials cannot read another user's object or assume an unrelated role. Never ship permanent IAM keys or administrator permissions to app clients.

## References

- [Cognito models/scenarios](https://docs.aws.amazon.com/cognito/latest/developerguide/what-is-amazon-cognito.html).
- [App clients and PKCE](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-client-apps.html).
- [Access-token claims](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-using-the-access-token.html).
- [JWT verification](https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-tokens-verifying-a-jwt.html).
- [Resource servers and custom scopes](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-define-resource-servers.html).
- [HTTP JWT authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html).
- [Pricing](https://aws.amazon.com/cognito/pricing/).
