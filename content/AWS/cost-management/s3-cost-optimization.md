---
title: S3 Cost Optimization
description: S3 cost optimization — storage classes, lifecycle policies, Intelligent-Tiering, data retrieval costs, replication costs, and S3 Analytics
tags:
  - aws
  - cost-management
  - storage
---

# S3 Cost Optimization

S3 pricing has four components: storage (per GB-month), requests (per 1,000 requests), data transfer (out of S3 to internet or across regions), and optional features (Object Lambda, Select, etc.). Most people's S3 bill is dominated by storage, but data transfer can surprise at scale.

## Storage Classes

S3 offers seven storage classes across two axes: access frequency and durability.

| Class | Use When | GB/Month | Retrieval |
|-------|----------|----------|-----------|
| **Standard** | Frequently accessed (< 90 days) | ~$0.023 | Free |
| **Intelligent-Tiering** | Unknown/unpredictable access | $0.023 + monitoring | Free |
| **Standard-IA** | Infrequent (accessed 1-3x/month) | ~$0.0125 | $0.01/GB |
| **One Zone-IA** | Re-creatable, infrequent | ~$0.01 | $0.01/GB |
| **Glacier Instant Retrieval** | Rarely accessed, needs ms retrieval | ~$0.004 | $0.004/GB |
| **Glacier Flexible Retrieval** | Archival, 1min-12hr retrieval | ~$0.001 | $0.03-0.01/GB |
| **Glacier Deep Archive** | Long-term retention, 12hr+ retrieval | ~$0.00099 | $0.09-0.01/GB |

**Key decision:** Is the data re-creatable? If yes, One Zone-IA saves 20% over Standard-IA. Is retrieval time critical? Instant Retrieval costs more than Flexible but delivers in milliseconds.

**Object size consideration:** Objects < 128KB are charged for the minimum object size in Glacier classes. Small objects don't benefit from Glacier pricing.

## Lifecycle Policies

Lifecycle policies automatically transition objects between storage classes or expire them. They're the primary mechanism for cost optimization — you set rules once, S3 applies them automatically.

**Transition actions:**
```
Rule 1: Move to Standard-IA after 30 days
Rule 2: Move to Glacier after 90 days
Rule 3: Move to Deep Archive after 1 year
Rule 4: Move to Intelligent-Tiering after 0 days (auto-optimize)
```

**Expiration actions:**
```
Rule 5: Delete incomplete multipart uploads after 7 days
Rule 6: Delete objects with tag "Cleanup=true" after 90 days
Rule 7: Delete previous versions after 1 year (if versioning enabled)
```

**Noncurrent version transitions:** If versioning is enabled, configure how many days after an object becomes a noncurrent version before it transitions.

**Anti-pattern:** Don't transition objects directly from Standard to Glacier if they're accessed frequently in the first 30 days. Use Standard-IA as an intermediate step or use Intelligent-Tiering.

## Intelligent-Tiering

The automatic storage class that monitors access patterns and moves objects to the appropriate tier. Two monitoringfees apply: $0.0025 per 1,000 objects per month.

**Tiers:** Frequent → Infrequent → Archive Instant → Deep Archive (automatic)

**Good for:** Data with unknown or unpredictable access patterns — backups, analytics data, regulatory archives where you don't know when/if it will be accessed.

**Not good for:** Objects < 128KB (minimum object size charge applies), very small buckets with high request counts (monitoring fees add up), data accessed on predictable schedules (lifecycle rules are more cost-effective).

## Data Retrieval Costs

This is where people get surprised. S3 charges for data retrieved from Standard-IA, One Zone-IA, Glacier Flexible Retrieval, and Deep Archive.

**Example:** You have 10TB in Standard-IA and someone runs a full scan of it. Retrieval cost alone: 10TB × $0.01/GB = ~$100.

**Mitigation:**
- Use S3 Select to retrieve only the data you need from objects (CSV, JSON, Parquet)
- Use Athena instead of retrieving entire objects
- Set lifecycle rules so frequently-accessed data stays in Standard
- Use Intelligent-Tiering for unknown access patterns (no retrieval fees in the monitoring tier)

## Replication Costs

S3 Replication (CRR/SRR) has two cost components:

1. **Inter-region data transfer** — data leaving the source region and entering the destination region. ~$0.02-0.05/GB depending on region pair.

2. **S3 request charges** — per-object replication request. PUT, COPY, metadata updates all cost replication requests.

**S3 Same-Region Replication (SRR):** No inter-region transfer charge, but still request charges. Useful for compliance (cross-account replication to a dedicated audit account) or log aggregation.

**S3 Replication Time Control:** Guarantees replication within 15 minutes. Costs more than standard replication due to priority queue.

**S3 Batch Replication:** Replicate objects that failed replication, objects created before replication was enabled, or objects with existing data. Useful for migrating existing data to a new replication configuration.

## Data Transfer Out

S3 data transfer out to internet is priced at ~$0.09/GB (varies by region). This is one of the most common unexpected costs.

**Optimization:**
- Use CloudFront in front of S3 — CloudFront origin fetch is free, CloudFront egress is cheaper than S3 direct egress for large audiences
- Keep data in the same region — S3 data transfer to AWS services in the same region is free (Lambda, EC2, CloudWatch)
- Use VPC endpoints to access S3 privately without going through the internet (no data transfer charge for S3→EC2 within region)

## S3 Analytics

S3 Analytics → Storage Lens gives visibility into:
- Which prefixes/buckets are growing fastest
- How many objects in each storage class
- Which objects haven't been accessed in X days
- Transition planning — "if you set a lifecycle to move objects to IA after 90 days, X% of objects would qualify today"

Use S3 Analytics before designing lifecycle policies — it tells you the actual access patterns, not assumptions.

## Anti-Patterns to Avoid

- **Storing everything in Standard.** If half your bucket hasn't been accessed in 2 years, you're paying Standard pricing for archival data.
- **No lifecycle for incomplete multipart uploads.** These sit in your bucket forever and cost money.
- **No versioning analysis.** Old versions of frequently-overwritten objects can double or triple your storage bill.
- **Ignoring S3 Select.** Retrieving full objects when you only need 5% of the data wastes both transfer and compute costs on whatever is reading the data.

## References

- **Homepage:** https://aws.amazon.com/s3/pricing/
- **Documentation:** https://docs.aws.amazon.com/AmazonS3/latest/userguidegsg.html
- **Pricing:** https://aws.amazon.com/s3/pricing/

## Pricing Examples

**Scenario 1:** A data lake with 100TB of Parquet files in S3 Standard. Access pattern: data analysts query via Athena 2-3 times per week. Most objects are accessed once a month, some never. Moving 60TB to S3 Intelligent-Tiering: S3 Standard (100TB × $0.023 = $2,300/month) vs Intelligent-Tiering (60TB IST + 40TB Standard = $230 + $920 = $1,150/month). Savings: ~$1,150/month.

**Scenario 2:** A media company storing 500GB of user-uploaded images. Most uploads are accessed within 48 hours of upload, then rarely again. Lifecycle: Standard for 30 days, then One Zone-IA for 60 days, then delete. Monthly cost: (500GB × $0.023) + (500GB × $0.0125 for 30 days) = $11.50 + $6.25 = ~$18/month vs keeping all in Standard: $11.50/month — actually more expensive due to transition costs. Better: Intelligent-Tiering auto-manages this at ~$0.0125/month average.

## Nuggets & Gotchas

- **S3 Intelligent-Tiering has a 128KB minimum object size:** Objects smaller than 128KB don't benefit from Intelligent-Tiering's automatic transitions — they're charged at the frequent access tier rate regardless. For small objects, manually move to Glacier or One Zone-IA.
- **S3 lifecycle transitions are based on object age, not access time:** An object in Standard doesn't reset its transition clock when you read it. If you read a 2-year-old object from Standard, it still qualifies for Glacier transition based on creation date, not last access.
- **S3 egress charges apply to every GB leaving S3:** CloudFront can reduce origin request costs by caching at edge locations. If your S3 data is accessed frequently from the internet, a CloudFront distribution in front of the bucket saves on S3 egress (CloudFront → internet pricing is lower than S3 → internet).
- **Cross-region replication (CRR) doubles storage costs:** You pay storage in both source and destination regions. CRR costs often surprise people who enabled it for disaster recovery but didn't account for the storage duplication cost.
- **S3 Glacier Deep Archive has a 180-day minimum storage duration:** If you delete before 180 days, you pay for the full 180 days. Similarly, S3 Intelligent-Tiering has a 90-day minimum for Deep Archive transition.