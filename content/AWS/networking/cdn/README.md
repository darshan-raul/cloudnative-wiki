---
title: "Amazon CloudFront"
description: "Design cache keys and private origins, test personalized/range behavior and model geography-aware delivery costs."
tags:
  - cloud/aws/networking/cdn
date: 2026-10-12
---

# Amazon CloudFront

CloudFront caches and delivers supported content through edge infrastructure. Correct cache isolation and origin authorization matter more than a generic “CDN is cheaper” claim. Start with [[AWS/storage/s3/README|S3]] and [[AWS/networking/dns/README|DNS]].

## Cache key versus origin request

The default cache key includes distribution domain and URL path. A cache policy can add selected headers, query strings and cookies. An origin request policy can forward extra values **without** adding them to the key; forwarding a user identity without safe cache isolation can expose another user's response.

A response Set-Cookie does not automatically add the cookie to the request key. Review whether headers/cookies can be replayed from cache and disable caching or design isolation for personalized responses.

TTL comes from the cache policy and applicable origin headers/behavior; do not promise every object always lives exactly twenty-four hours. CloudFront supports range GETs/206 with documented origin/range conditions.

## Private origin

For supported S3 origins, use OAC and a scoped bucket policy; legacy OAI is a separate mechanism. S3 website endpoints have different integration/access constraints. A CloudFront distribution alone does not stop direct bucket access.

Functions and Lambda@Edge have different supported events, runtime/network/body capabilities and billing. Select from current contracts, not a generic interchangeability table.

## Cache correctness exercise

Prerequisites: a sandbox distribution/origin, two test variants and a budget. Use nonsensitive fixtures, not real user data.

1. Publish a static marker and inspect Cache-Control plus cache-hit/miss headers over repeated requests.
2. Add a query parameter that changes the origin response. Compare behavior before and after adding that parameter to the cache key.
3. Test a cookie-dependent fixture; prove two clients cannot receive each other's personalized result.
4. Request a valid byte range and verify the response and origin behavior.
5. Update a versioned filename or perform a bounded invalidation, then measure propagation instead of assuming a guaranteed number of minutes.

For private S3 access, verify CloudFront success and unauthorized direct-S3 denial. Record distribution identity, policies and expected cache responses.

## Cost and cleanup

Price viewer geography/transfer tier, HTTP/HTTPS request counts, optional Origin Shield requests, functions, invalidations and other selected features. Origin Shield is not a universal per-GB surcharge, and ALB/S3/CloudFront do not share one transfer tariff.

Disable and delete only the dedicated distribution through its supported lifecycle, then remove dedicated origin/policy/artifacts/logs after checking dependencies. Disabling a distribution alone does not clean up its origin.

## Distribution path and feature choices

```text
viewer → DNS → CloudFront distribution → ordered cache behavior
                               ├─ cache key/TTL → edge response
                               ├─ origin request policy → origin fetch
                               └─ S3 with OAC or approved HTTP origin
```

Each behavior selects an origin and cache policy. The cache key determines which requests may share a cached response; the origin request policy determines which additional values reach the origin. Design both for authentication and localization. For a single-page app, HTML usually needs a short or controlled TTL while fingerprinted assets can be cached longer. A versioned asset name is often easier to roll back than repeatedly invalidating a broad path.

CloudFront Functions suit lightweight viewer-side request/response changes within their supported runtime; Lambda@Edge supports a broader event model and different deployment/runtime limits. Neither is a substitute for authorizing private origin access. Signed URLs/cookies control viewer access when appropriate; OAC controls CloudFront-to-S3 access. WAF/Shield address different threat classes from cache policy or origin identity.

| Capability                     | CloudFront Functions                                     | Lambda@Edge                                                        |
| ------------------------------ | -------------------------------------------------------- | ------------------------------------------------------------------ |
| Languages                      | Supported JavaScript runtimes                            | Supported Node.js/Python runtimes                                  |
| Events                         | Viewer request/response                                  | Viewer and origin request/response                                 |
| Network or request-body access | No                                                       | Supported with event-specific limits                               |
| CloudFront KeyValueStore       | Supported with JavaScript runtime 2.0                    | No                                                                 |
| Common use                     | URL/cache-key/header changes, supported token validation | Origin logic or processing requiring libraries/network/body access |

Check [the current edge-function comparison](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/edge-functions-choosing.html) for event quotas and runtime support before packaging code.

### Viewer and origin TLS

For a custom viewer hostname, request/import the ACM certificate in **us-east-1**, validate the domain, attach it to the distribution and add the alternate domain name. Its certificate SAN must cover that name exactly or through a valid wildcard. Set the intended viewer HTTPS policy and test the custom hostname after DNS/configuration propagation.

CloudFront-to-origin HTTPS is a separate connection with its own origin protocol policy and valid certificate/name requirements. An ALB origin uses a certificate in the ALB's Region. A successful viewer handshake does not establish that the origin handshake works; mismatched origin names or chains can produce backend errors. Follow [CloudFront certificate requirements](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html) and test both legs.

### Static site plus API example

| Ordered path behavior | Origin                        | Cache design                                                  |
| --------------------- | ----------------------------- | ------------------------------------------------------------- |
| `/assets/*`           | Private S3 bucket through OAC | Long TTL for fingerprinted filenames; omit user cookies       |
| `/api/*`              | HTTPS application origin      | Disable shared caching unless each variant is safely isolated |
| Default `/*`          | Private S3 origin             | Deliberate HTML TTL and SPA fallback behavior                 |

Test a personalized API request from two separate clients. If the origin varies on a cookie or Authorization header, either avoid shared caching for that behavior or include a safe variation key. Forwarding the header without including it in a cache key can expose one client's response to another. For origin access, confirm a CloudFront request succeeds while direct S3 access is denied under the bucket policy.

For planned asset changes, publish a new fingerprinted filename. For a bounded emergency invalidation, record the distribution ID and requested paths, then run `aws cloudfront create-invalidation --distribution-id "$CF_LAB_DISTRIBUTION_ID" --paths '/index.html'`. Inspect status before assuming propagation is complete; avoid a global `/*` invalidation by default. Geo restrictions and price class constrain delivery geography, but neither is a substitute for application authorization or a complete global cost estimate.

### Worked delivery estimate

For a hypothetical North American viewer-delivery study dated 2026-10-12, suppose ten million requests each return a 50 KiB asset from an origin in us-east-1. That is about 476.8 GiB of viewer transfer before cache effectiveness is considered. At assumed inputs of \$0.08/GiB delivery and \$0.01 per 10,000 requests, the arithmetic is about \$38.15 for delivery plus \$10 for requests. Replace these study inputs with the selected geography/plan and include origin fetches, invalidations beyond allowances, functions, logs and any application origin costs. A higher cache-hit rate primarily reduces origin work; it does not make viewer delivery bytes disappear.

When diagnosing a wrong response, record behavior match, cache key values, response Cache-Control, `Age`, cache status and whether the origin received the request. A 403 can come from viewer policy, WAF, origin authorization or missing object; a cache hit does not prove the origin is healthy. Range requests and compressed variants deserve separate tests because their origin and caching behavior can differ from a full object GET.

## References

- [Default/custom cache keys](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/understanding-the-cache-key.html).
- [Cookie behavior](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Cookies.html).
- [Range GETs](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/RangeGETs.html).
- [OAC](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html).
- [Pricing](https://aws.amazon.com/cloudfront/pricing/).

## Across the wiki

- [[GCP/networking/cloud-cdn/README|GCP Cloud CDN Architecture & Edge Caching]] — CDN and edge caching (GCP)
- [[Architecture/solution-architecture-concepts/data-architecture/cdn|CDN]] — CDN and edge caching (Architecture)
- [[Architecture/solution-architecture-concepts/caching|Caching]] — CDN and edge caching (Architecture)
