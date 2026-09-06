---
title: GCP Cloud CDN Architecture & Edge Caching
description: Cloud CDN architecture — Google edge Points of Presence (PoPs), cache modes, cache key customization, negative caching, signed URLs/cookies, and cache invalidation.
tags:
  - gcp
  - networking
  - cdn
  - cloud-cdn
  - performance
---

# GCP Cloud CDN Architecture & Edge Caching ⚡🌍

Google Cloud CDN uses Google's globally distributed Edge Points of Presence (PoPs) to cache HTTP/HTTPS content as close to users as possible. Built directly into the **Google Global External Application Load Balancer**, Cloud CDN terminates TCP and TLS connections at Google's edge, offloading over **80% of origin web traffic** and cutting egress bandwidth costs by more than **50%**.

---

## Architecture & Mental Model

### Edge Caching Topology & Request Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Worldwide Edge Users                            │
│           (Clients in Tokyo, Sydney, London, New York)                 │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Incoming HTTP GET
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     Google Edge Points of Presence (PoPs)              │
│                     (Anycast IP: Single Global Static IPv4)            │
│                                                                        │
│   1. Terminate TCP & TLS Handshake at the nearest physical PoP         │
│   2. Compute Cache Key (Host, Path, Query Params, Headers)             │
│   3. Cache Lookup in Local Edge RAM / NVMe SSD                         │
│      ├── CACHE HIT ──────────────────────────────► Return Bytes (10ms) │
│      └── CACHE MISS                                                    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Fetch from Origin over Google Backbone
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                       Origin Infrastructure                            │
│                                                                        │
│   • Cloud Storage Buckets (gs://prod-media-assets)                     │
│   • GKE Pods via Zonal NEGs                                            │
│   • Serverless Containers via Cloud Run Serverless NEGs                │
│   • External On-Premises Origins via Internet NEGs                     │
└────────────────────────────────────────────────────────────────────────┘
```

* **The Anycast Edge Advantage:** Unlike DNS-based CDNs that require regional CNAME hopping, user traffic hits the nearest Google Edge PoP over a single Anycast IP. Cache misses travel over Google's private global fiber backbone to the origin rather than traversing the public internet.

---

## Core Concepts

### 1. Cache Modes

| Cache Mode | Behavior | Best For |
| :--- | :--- | :--- |
| **`CACHE_ALL_STATIC` (Default)** | Automatically caches static content (images, videos, CSS, JS) based on standard file extensions. Respects `no-store` / `private`. | Standard web apps, frontend SPAs, blog sites |
| **`USE_ORIGIN_HEADERS`** | Strictly obeys origin response headers (`Cache-Control`, `Expires`). Does not cache unless origin explicitly permits it. | Enterprise APIs with custom dynamic caching logic |
| **`FORCE_CACHE_ALL`** | Unconditionally caches all responses, completely overriding origin `Cache-Control: private` or `no-cache` headers. | Public static websites, firmware distribution |

### 2. Cache Key Customization

A **Cache Key** is the unique identifier string used to index and look up cached content. By default, the cache key includes: `Protocol + Host + Path + All Query Parameters`.
* **Excluding Query Parameters:** If your marketing campaigns append tracking query parameters (`?utm_source=twitter&utm_medium=cpc`), standard caching treats every URL as a separate cache entry, causing a near-zero cache hit ratio!
* Configure Cloud CDN to exclude query parameters to normalize cache keys:
```
Request 1: /images/banner.png?utm_source=google ──► Key: /images/banner.png
Request 2: /images/banner.png?utm_source=fb     ──► Key: /images/banner.png (CACHE HIT!)
```

### 3. Negative Caching (Protecting Origins Against Thundering Herds)

When an origin returns an error (such as `HTTP 404 Not Found` or `HTTP 502 Bad Gateway`), clients and scrapers frequently retry aggressively, overwhelming the origin:
* **Negative Caching:** Caches error responses for a short configurable window (e.g. 10 seconds for 404s, 5 seconds for 502s).
* Shields backend microservices from denial-of-service traffic during backend database degradation.

### 4. Signed URLs & Signed Cookies

Restricts media access to authorized, paying users without making storage buckets public:
* **Signed URLs:** Embeds an HMAC cryptographic signature and expiration timestamp directly into the URL query parameters.
* **Signed Cookies:** Injects a signed session cookie into the client's browser, permitting access to an entire directory tree of private files (e.g. video streaming HLS/DASH playlists).

---

## Production `gcloud` CLI Commands

### 1. Enabling Cloud CDN on a Backend Service with Custom Cache Keys

```bash
gcloud compute backend-services update prod-web-backend \
  --global \
  --enable-cdn \
  --caching-mode=CACHE_ALL_STATIC \
  --default-ttl=3600 \
  --max-ttl=86400 \
  --client-ttl=1800 \
  --custom-response-header="X-Cache-Status: {cdn_cache_status}" \
  --cache-key-query-string-whitelist=id,version \
  --cache-key-include-host \
  --cache-key-include-protocol
```

* `--cache-key-query-string-whitelist=id,version`: Normalizes cache keys by stripping all marketing UTM tags while preserving critical application query arguments.

### 2. Configuring Negative Caching for Resiliency

```bash
gcloud compute backend-services update prod-web-backend \
  --global \
  --enable-negative-caching \
  --negative-caching-policy="404=10,502=5,503=5"
```

### 3. Invalidating Cache Content

```bash
# Invalidate all cached images under /static/images/
gcloud compute url-maps invalidate-cdn-cache prod-url-map \
  --path="/static/images/*" \
  --async
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max cacheable object size** | 5 TiB per object | Supports massive video assets |
| **Max concurrent cache invalidations** | 1 concurrent invalidation per URL map | Use versioned asset names (`app.v2.js`) |
| **Cache key size limit** | 4,096 bytes | Normalize long query strings |
| **Custom headers per backend** | Up to 16 custom headers | Useful for debugging cache hit states |

---

## References

* **Cloud CDN Overview:** https://cloud.google.com/cdn/docs/overview
* **Cache Modes Guide:** https://cloud.google.com/cdn/docs/caching-details
* **Cache Keys Documentation:** https://cloud.google.com/cdn/docs/using-cache-keys
* **Signed URLs and Cookies:** https://cloud.google.com/cdn/docs/using-signed-urls
* **Pricing:** https://cloud.google.com/cdn/pricing

---

## Pricing Examples

### Scenario 1: SaaS Web Application (Static Asset Offload)
* Monthly outbound traffic from Cloud Storage origin: 20 TB without CDN.
* With Cloud CDN enabled: **85% Cache Hit Ratio** (17 TB served from Edge Cache; 3 TB fetched from origin).
* CDN Cache Fill (Fetch from GCS to Edge): 3 TB × $0.01 / GB = $30.00.
* CDN Edge Egress to Users: 20 TB × ~$0.05 / GB = $1,000.00.
* Direct GCS Egress without CDN would have cost: 20 TB × $0.12 / GB = $2,400.00.
* **Monthly Savings with Cloud CDN:** **~$1,370.00 / month** (57% net reduction in egress billing).

### Scenario 2: High-Volume Media Streaming Platform
* 100 TB of video files streamed to worldwide audiences.
* 92% Cache Hit Ratio.
* CDN Egress: 100 TB (tiered discount: ~$0.04 / GB) = **$4,000.00 / month**.
* HTTP Request fees (100 million cache hits @ $0.0075 / 10,000): **$75.00 / month**.
* **Total Monthly CDN Bill:** **~$4,075.00 / month**.

---

## Nuggets & Gotchas

1. **`Set-Cookie` Headers Disable Caching by Default:** If your backend web framework (e.g. Django, Express, Rails) emits a `Set-Cookie` header in its HTTP response, Cloud CDN **refuses to cache the response** to prevent leaking one user's private session cookie to other users. If you are caching static pages, configure your framework to strip cookies from static routes or set `Cache-Control: public`.
2. **Cache Invalidation Delays vs. Cache Busting:** Cache invalidation via `invalidate-cdn-cache` takes **several minutes** to propagate across all 100+ worldwide edge PoPs and is rate-limited to 1 concurrent invalidation. Modern production architectures practice **Cache Busting** (embedding content hashes into file names: `bundle.a8f9c2.js`), which requires zero invalidation and enables permanent immutable caching (`max-age=31536000`).
3. **Query String Churn Destroys Cache Hit Ratios:** If your web application receives requests with random query parameters (e.g. cache-busting timestamps `?_=1693982400` or Google Ads `?gclid=...`), Cloud CDN treats every single request as a cache miss. Always configure a **Query String Whitelist** on the cache key to ignore irrelevant parameters.
4. **Cloud CDN Requires the Global External Application Load Balancer:** Cloud CDN cannot be attached directly to a Cloud Storage bucket or a Compute Engine VM in isolation. It **strictly requires** a Global External Application Load Balancer (or Regional External ALB in supported configurations).
5. **Negative Caching Prevents Deployment Blackouts:** If a newly deployed backend version crashes on startup and returns `HTTP 502 Bad Gateway`, clients repeatedly hammering the endpoint can permanently keep the backend overloaded. Enabling negative caching (`502=5s`) gives the backend breathing room to recover by caching the error at the edge for 5 seconds.
