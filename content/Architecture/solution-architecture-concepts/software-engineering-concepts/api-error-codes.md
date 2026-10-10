---
title: API Error Codes, HTTP Status Standards & RFC 7807 Problem Details
description: Professional API error handling — 4xx vs 5xx taxonomy, 401 vs 403 distinctions, RFC 7807 Problem Details format, and avoiding security information leakage
tags:
  - architecture
  - api-design
  - http
  - rfc7807
  - rest
date: 2026-01-30
---

# API Error Codes, HTTP Status Standards & RFC 7807 Problem Details

High-quality API design treats error handling as a first-class contract. Returning generic `{"error": "something went wrong"}` or worse, `200 OK {"status": "error"}` (the GraphQL anti-pattern) cripples client observability and automated retry mechanisms.

---

## 1. The Definitive HTTP Status Code Taxonomy

```
2xx: Success (The client did the right thing, and it worked)
3xx: Redirection (The resource moved, go elsewhere)
4xx: Client Error (The client did something wrong, do NOT retry without changes)
5xx: Server Error (The server failed, client MAY retry with backoff)
```

### Critical 4xx Client Errors:

- **`400 Bad Request`:** Malformed JSON, unparseable query syntax, invalid request framing.
- **`401 Unauthorized`:** **Unauthenticated.** The client failed to provide valid credentials (missing Bearer token, expired signature). The response **MUST** include a `WWW-Authenticate` header.
- **`403 Forbidden`:** **Authenticated, but unauthorized.** The server knows who you are, but you lack permission to perform this action. Retrying with the same credentials will never succeed.
- **`404 Not Found`:** The resource does not exist (or the server conceals existence to prevent enumeration).
- **`409 Conflict`:** State conflict, e.g. optimistic concurrency locking failure or duplicate email violation.
- **`422 Unprocessable Content`:** The JSON syntax is valid, but fails semantic domain validation rules (e.g. `age: -5` or invalid phone number).
- **`429 Too Many Requests`:** Rate limit exceeded.

### Critical 5xx Server Errors:

- **`500 Internal Server Error`:** Unhandled application exception or crash.
- **`502 Bad Gateway`:** Reverse proxy/gateway received an invalid or terminated response from upstream origin.
- **`503 Service Unavailable`:** Server overloaded, undergoing maintenance, or circuit breaker tripped.
- **`504 Gateway Timeout`:** Upstream backend service failed to respond within proxy read timeout window.

---

## 2. Standardized Error Responses: RFC 7807 (Problem Details)

Instead of ad-hoc JSON dictionaries, adopt **RFC 7807 / RFC 9457 (Problem Details for HTTP APIs)**:

- Content-Type: `application/problem+json`

### Example: Validation Failure

```http
HTTP/1.1 422 Unprocessable Content
Content-Type: application/problem+json

{
  "type": "https://api.cloudnative.wiki/errors/invalid-parameters",
  "title": "Your request parameters failed validation",
  "status": 422,
  "detail": "The provided credit card number has expired.",
  "instance": "/v1/payments/tx_998811",
  "invalid_params": [
    {
      "name": "expiry_year",
      "reason": "Year must be greater than current calendar year."
    }
  ]
}
```

---

## 3. Security Considerations: Information Leakage

> [!CAUTION]
> **Never leak raw stack traces or internal database errors to clients.**  
> Revealing database engine versions, table names, or internal file paths assists attackers in crafting targeted SQL injections and exploits.

- **Client Response:** Return clean RFC 7807 errors with an opaque `error_id` / `trace_id`.
- **Internal Logs:** Log the full exception, call stack, and context in your internal APM / SIEM correlated to that same `trace_id`.

## Across the wiki

- [[AWS/serverless/api-gateway/README|Amazon API Gateway]] — API design and gateways (AWS)
- [[AWS/application-integration/appsync/README|AWS AppSync]] — API design and gateways (AWS)
