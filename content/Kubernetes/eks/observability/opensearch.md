---
title: OpenSearch for EKS Logs
tags: [eks, observability, logging, opensearch, fluent-bit]
date: 2026-05-17
description: Shipping EKS logs to Amazon OpenSearch Service — pipeline options, fine-grained access control and role mapping, index lifecycle, sizing, and when OpenSearch is the wrong log store.
---

# OpenSearch for EKS Logs

[[AWS/analytics/opensearch/README|Amazon OpenSearch Service]] is a managed search and analytics engine. As a log backend it offers what [[AWS/monitoring/cloudwatch-logs/README|CloudWatch Logs]] does not: fast full-text search across everything, rich dashboards, and aggregations over arbitrary fields. The price is a cluster that you size, secure and tune.

## Getting logs in

| Pipeline                                           | Path                                                   | Choose when                                                      |
| :------------------------------------------------- | :----------------------------------------------------- | :--------------------------------------------------------------- |
| Fluent Bit → OpenSearch                            | DaemonSet writes straight to the domain                | Simple, one cluster, modest volume                               |
| Fluent Bit → OpenSearch Ingestion → OpenSearch     | A managed Data Prepper pipeline buffers and transforms | You want buffering, enrichment and back-pressure handled for you |
| Fluent Bit → Firehose → OpenSearch (+ S3 backup)   | Managed delivery stream                                | You also want a cheap raw archive                                |
| CloudWatch Logs → subscription filter → OpenSearch | Reuses existing CloudWatch ingestion                   | Logs are already in CloudWatch and you pay twice knowingly       |

Direct output is the baseline:

```ini
[OUTPUT]
    Name                opensearch
    Match               kube.*
    Host                vpc-logs-abc123.eu-west-1.es.amazonaws.com
    Port                443
    TLS                 On
    AWS_Auth            On
    AWS_Region          eu-west-1
    Logstash_Format     On
    Logstash_Prefix     eks-app
    Suppress_Type_Name  On
    Replace_Dots        On
    Trace_Error         On
    Retry_Limit         5
```

`Logstash_Format` creates one index per day (`eks-app-2026.10.10`), which is what makes retention manageable. `Replace_Dots` avoids mapping conflicts from Kubernetes labels such as `app.kubernetes.io/name`. The collection side is described in [[Kubernetes/eks/observability/logging/pod-logging|pod logging]].

## Access: two layers that both must agree

This is where most first attempts fail with `403 Forbidden`.

1. **[[AWS/security/iam/README|IAM]] and the domain access policy** decide whether the request reaches OpenSearch. Fluent Bit signs requests with the role it gets from [[Kubernetes/eks/security/pod-identity|Pod Identity]] or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]]; the role needs `es:ESHttpPost` and `es:ESHttpPut` on the domain.
2. **Fine-grained access control** inside OpenSearch decides what that identity may do. The IAM role must be mapped to an OpenSearch role as a _backend role_.

```bash
curl -XPUT "https://<domain>/_plugins/_security/api/rolesmapping/log_writer" \
  -u admin -H 'Content-Type: application/json' -d '{
    "backend_roles": ["arn:aws:iam::111122223333:role/fluent-bit"]
  }'
```

Give the writer role only `create_index` and `index` on the log index pattern. Readers get a separate role, ideally federated through SAML or IAM Identity Center. Use index- or document-level security when teams must not see each other's logs.

Put the domain in the [[AWS/networking/vpc/README|VPC]], in private subnets, with a [[AWS/networking/vpc/security-groups|security group]] that allows 443 only from the nodes and from wherever people reach Dashboards.

## Index lifecycle

Logs are write-once and lose value quickly, so automate their ageing with an Index State Management policy:

| Phase  | Age         | Action                                                  |
| :----- | :---------- | :------------------------------------------------------ |
| Hot    | 0–3 days    | Indexed on fast storage, replicas on                    |
| Warm   | 3–30 days   | Moved to UltraWarm (S3-backed, read-only), force-merged |
| Cold   | 30–180 days | Detached to cold storage; attach on demand to query     |
| Delete | > 180 days  | Index deleted                                           |

Without a policy, the domain fills up. At 85% disk usage OpenSearch stops allocating shards, and soon after blocks writes; Fluent Bit then retries, buffers and eventually drops logs.

## Sizing rules of thumb

- **Shards** are the unit of work. Aim for 10–50 GB per shard and avoid thousands of tiny shards: each one costs heap. Daily indices for a small volume create exactly that problem — use rollover by size instead.
- **Storage** = daily volume × (1 + replicas) × retention in hot × ~1.25 for overhead.
- **Dedicated master nodes** (three) for anything in production.
- **Three zones** with replicas, so losing a zone loses no data.
- **Explicit index templates.** Dynamic mapping turns every new JSON key into a field. A service that logs arbitrary keys causes a _mapping explosion_ and rejected documents. Define a template, map noisy objects as `flat_object`, and cap `index.mapping.total_fields.limit`.

OpenSearch **Serverless** removes sizing: a time-series collection scales capacity automatically and is paid per capacity unit. It suits unpredictable or small workloads, with a higher floor price and fewer tuning knobs.

## Is OpenSearch the right log store?

|                     | CloudWatch Logs         | OpenSearch                 | Loki                                |
| :------------------ | :---------------------- | :------------------------- | :---------------------------------- |
| Operations          | None                    | Significant                | Moderate                            |
| Full-text search    | Scan-based (Insights)   | Indexed, fast              | Label-select then scan              |
| Cost at high volume | High ingestion price    | High compute and storage   | Low (object storage)                |
| Dashboards          | Basic                   | OpenSearch Dashboards      | [[Observability/grafana\|Grafana]]  |
| Also useful for     | Alarms, AWS integration | Security analytics, traces | Correlating with Prometheus metrics |

OpenSearch earns its cost when people search logs interactively every day, or when the same domain also serves security analytics ([[Security/siem/README|SIEM]]). If logs are mostly consulted during incidents, a cheaper store is usually enough — see [[Observability/logging|logging]].

## Troubleshooting

| Symptom                                           | Cause                                                                                      |
| :------------------------------------------------ | :----------------------------------------------------------------------------------------- |
| `403` from Fluent Bit                             | Role not mapped as a backend role, or domain policy excludes it                            |
| `429 Too Many Requests` / `es_rejected_execution` | Write thread pool saturated: too many shards or undersized nodes                           |
| `mapper_parsing_exception`                        | The same field arrived as a string and as an object — fix at the source or with a template |
| Writes blocked, `FORBIDDEN/12/index read-only`    | Disk watermark reached; delete old indices, then clear the block                           |
| Cluster status red                                | Unassigned primary shards; check `_cluster/allocation/explain`                             |

## Related

- [[Kubernetes/eks/observability/README|EKS observability overview]]
- [[Kubernetes/eks/observability/logging/control-plane-logs|Control plane logs]]
- [[Security/siem/elastic-security/README|Elastic Security]] and [[Security/siem/wazuh/README|Wazuh]] — the same engine family used for detection
- [Amazon OpenSearch Service developer guide](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/what-is.html)

## Across the wiki

- [[Linux/observability/journalctl|journalctl]] — host and container logs (Linux)
- [[Linux/concepts/08-logging|08 — Logging]] — host and container logs (Linux)
