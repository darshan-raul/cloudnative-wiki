---
title: Amazon CloudFront
description: Amazon CloudFront — global CDN with edge caching, SSL/TLS termination, OAI, Lambda@Edge and CloudFront Functions, and DDoS protection via Shield Standard.
tags:
  - aws
  - networking
  - cdn
  - cloudfront
---

# Amazon CloudFront

CloudFront is AWS's global content delivery network (CDN). It caches content at edge locations worldwide, reducing latency for end users and offloading origin traffic. CloudFront integrates with AWS Shield for DDoS protection (included at no extra cost).

## Core Concepts

### How CloudFront Works

```
User → Edge Location (cache hit) → Response (fast)
User → Edge Location (cache miss) → Origin (S3/ALB/EC2) → Response cached at edge
```

1. User requests content from a CloudFront URL (e.g., `d123.cloudfront.net/assets/logo.png`)
2. CloudFront checks the nearest edge location's cache
3. **Cache hit:** Returns cached content immediately
4. **Cache miss:** CloudFront fetches from the origin, caches it, and returns to the user

### Distributions

A distribution is a CloudFront configuration. Two types:

**Web Distributions** — HTTP/HTTPS, single or multiple origins, caching behavior, functions
**RTMP Distributions** — Adobe Media Server streaming (deprecated, avoid)

### Origins

An origin is the source of the content CloudFront caches:

| Origin Type | Use Case |
|------------|----------|
| S3 bucket | Static assets (images, videos, documents) |
| ALB | Dynamic content, API responses, authenticated content |
| EC2 | Direct to web server (not recommended — use ALB) |
| Custom HTTP origin | Non-AWS HTTP servers |
| MediaPackage channel | Live streaming |
| SageMaker endpoint | ML inference at the edge |

### Caching Behaviors

Caching behaviors control how CloudFront caches content:

```
Path pattern: /static/*
  → Origin: S3 bucket (static-assets)
  → Viewer protocol policy: HTTPS only
  → TTL: 86400 seconds (1 day)
  → Compress: Yes

Path pattern: /api/*
  → Origin: ALB (app-tier)
  → Viewer protocol policy: HTTPS only
  → TTL: 0 (no caching)
  → Allowed HTTP methods: GET, POST

Path pattern: /media/*
  → Origin: S3 bucket (media)
  → Viewer protocol policy: HTTPS only
  → TTL: 31536000 seconds (1 year)
  → Compress: No (video already compressed)
```

### Cache Key

The cache key determines what is cached. By default: `protocol + host + path + query string`

```
Cache key: https://d123.cloudfront.net/api/users?id=5
Cached separately from: https://d123.cloudfront.net/api/users?id=10
```

To cache regardless of query string: whitelist query params or use `CachePolicyId` that ignores query strings.

## Origin Access Identity (OAI)

OAI restricts S3 bucket access to CloudFront only. Without OAI, anyone can access S3 directly via the bucket URL. With OAI, only CloudFront can fetch from the bucket.

```
Without OAI:
 CloudFront → S3 bucket (public access enabled) → users can bypass CloudFront

With OAI:
 CloudFront → S3 bucket (public access disabled) → only CloudFront can access
```

## SSL/TLS

CloudFront terminates SSL/TLS at edge locations. Options:

**Default certificate:** A CloudFront-provided `*.cloudfront.net` certificate (free, auto-managed)

**Custom certificate (ACM):** Your own certificate via AWS Certificate Manager (free, AWS-provisioned)

**Origins:** Can use HTTP (CloudFront to origin) or HTTPS (encrypted end-to-end)

```
Viewer → CloudFront: Always encrypted (HTTPS required)
CloudFront → Origin: HTTP or HTTPS (configurable)
```

## CloudFront Functions and Lambda@Edge

Two ways to run code at CloudFront edge locations:

| Feature | CloudFront Functions | Lambda@Edge |
|---------|--------------------|-----------|
| Runtime | JavaScript only | Node.js, Python |
| Max execution time | < 3ms | 5-30 seconds |
| Pricing | Free tier + $0.10/million invocations | Paid per invocation + duration |
| Use case | Request/response manipulation | Complex logic, third-party auth |
| Can modify | Request headers, URL, query string | All headers, body, cookies |
| Access to | Request data only | Full AWS SDK |

### CloudFront Functions Use Cases

- **URL rewrites:** Redirect `/legacy/path` to `/new/path`
- **Header manipulation:** Add `X-Custom-Header` based on request
- **Query string manipulation:** Remove sensitive query params before caching
- **A/B testing:** Route to different origins based on cookie
- **Auth token validation:** Validate JWT before forwarding request

### Lambda@Edge Use Cases

- **Dynamic origin selection:** Route to different origins based on request characteristics
- **Custom error responses:** Return branded error pages from edge
- **Request authentication:** Validate OAuth tokens, API keys
- **Image resizing at edge:** Transform images on-the-fly (via Sharp, ImageMagick)

## Lambda@Edge Limitations

- **Cold starts:** Lambda@Edge has higher cold start latency than CloudFront Functions
- **Regional restriction:** Lambda@Edge runs in `us-east-1` region, then replicates to edge locations
- **Propagation delay:** Updating a Lambda@Edge function takes 5-10 minutes to propagate to all edge locations
- **Payload size:** 128KB request/response (vs 1MB for regular Lambda)
- **No persistent state:** Lambda@Edge cannot write to disk or databases directly

## AWS Shield (Included with CloudFront)

CloudFront automatically includes AWS Shield Standard:
- **DDoS protection** forLayer 3/4/7 attacks
- **Automatic mitigation** of common DDoS attacks
- **No extra cost**

**AWS Shield Advanced** ($3,000/month): Enhanced protection, 24/7 AWS DDoS response team, cost protection against DDoS-related scaling costs.

## Geo-Restriction

CloudFront can restrict content based on the viewer's country:

- **Whitelist:** Only serve content to specified countries
- **Blacklist:** Block specific countries

```
Geo-restriction: Enabled
Countries: [US, CA] (whitelist)
→ Requests from other countries get 403 Forbidden
```

## Invalidations

When origin content changes before the TTL expires, you can force CloudFront to re-fetch:

```bash
# Invalidate a single file
aws cloudfront create-invalidation --distribution-id EDFDVBD6EXAMPLE --paths "/logo.png"

# Invalidate all files
aws cloudfront create-invalidation --distribution-id EDFDVBD6EXAMPLE --paths "/*"
```

Invalidations are processed within 5-10 minutes globally. For emergency content removal (security incident), use invalidation. For planned origin updates, use versioned filenames or short TTLs.

## Price Classes

CloudFront pricing varies by geographic region. Reduce costs by excluding expensive regions:

- **All edge locations (default):** Full global coverage
- **Class 100:** Only NA + Europe (most expensive)
- **Class 200:** Class 100 + limited regions (India, Israel, South Africa)
- **Class All:** Everything, including Africa and Oceania (most expensive)

## Architecture: Static Site with CloudFront

```
Users → CloudFront (HTTPS)
           ↓ (cache miss)
      S3 bucket (static website hosting)
           ↓
      CloudFront caches at edge
```

## Architecture: SPA with API Backend

```
Browser → CloudFront → /static/* → S3 (static assets)
                    → /api/* → ALB (API, no cache)
                    → /* → index.html (S3, cached 1 hour)
```

## Limits

| Resource | Limit |
|----------|-------|
| Distributions per account | 200 |
| Cache behaviors per distribution | 25 |
| Origins per distribution | 25 |
| Files per invalidation | 1,000 (CLI), 3,000 (console) |
| Invalidation paths | 3,000 max per distribution |
| Alternate domain names | 100 per distribution |

## References

- **Homepage:** https://aws.amazon.com/cloudfront/
- **Documentation:** https://docs.aws.amazon.com/cloudfront/
- **Pricing:** https://aws.amazon.com/cloudfront/pricing/

## Pricing Examples

**Scenario 1:** A SaaS application serving 10M requests/month for static assets (JS, CSS, images) averaging 50KB each. 10M × 50KB = 500GB data transfer. CloudFront: 500GB × $0.0085/GB (first 10TB) = $4.25/month. Without CloudFront (direct from ALB): 500GB × $0.0085/GB (ALB data transfer) + ALB LCU cost ~$25/month. CloudFront saves ~$20/month and reduces latency.

**Scenario 2:** A global news site serving 500GB/day of video content. 500GB × 30 = 15TB/month. CloudFront (all regions): 15TB × $0.0085/GB = $127.50/month. Origin Shield enabled (us-east-1, $0.0075/GB): saves 80% on origin transfer = $127.50 + $102 = $229.50/month for 15TB but much lower origin load. vs no CloudFront (direct S3 + ALB): 15TB × $0.0085 + ALB = ~$400/month.

## Nuggets & Gotchas

- **CloudFront caches responses with Set-Cookie headers by default:** If your origin sets a cookie, CloudFront includes it in the cache key. This can cause cache fragmentation (every user gets a different cached response). Use `CachePolicy` to ignore cookies for static content.
- **CloudFront Functions cannot modify POST body or read full request bodies:** For JWT validation on POST requests, you need Lambda@Edge, not CloudFront Functions. CloudFront Functions have a 3ms time limit anyway, making complex auth impractical.
- **OAI doesn't work with S3 Transfer Acceleration:** If you enable S3 Transfer Acceleration on the bucket, OAI access breaks. Use CloudFront exclusively for S3 access, not Transfer Acceleration.
- **CloudFront default TTL is 24 hours:** A file cached at edge stays there for 24 hours even if you update it in S3. Use Cache-Control headers from origin or create invalidations. The `stale-while-revalidate` directive tells CloudFront to serve stale content while revalidating in background.
- **CloudFront does not cache HTTP 206 partial content by default:** For video streaming with byte-range requests, you need to configure CloudFront to cache 206 responses. Without it, every video segment request goes to the origin.
