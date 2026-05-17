---
title: OpenSearch for EKS Logs
tags: [eks, observability, logs, opensearch]
date: 2026-05-17
description: Log analysis with OpenSearch for EKS
---

# OpenSearch for EKS Logs

## Overview

Use OpenSearch for centralized log analysis and full-text search of application logs.

## Install OpenSearch

```bash
# Create OpenSearch domain
aws opensearch create-domain \
  --domain-name eks-logs \
  --engine-version OpenSearch_2.11 \
  --cluster-config InstanceType=m5.large.search,InstanceCount=2 \
  --ebs-options EBSEnabled=true,EBSVolumeSize=100 \
  --access-policies '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::123456789:root"},
      "Action": "es:*",
      "Resource": "arn:aws:es:us-west-2:123456789:domain/eks-logs/*"
    }]
  }'
```

## Install Fluent Bit with OpenSearch

```bash
helm install fluent-bit fluent/fluent-bit \
  --namespace kube-system \
  --set aws.region=us-west-2 \
  --set opensearch.enabled=true \
  --set opensearch.host=search-eks-logs-xxxxx.us-west-2.es.amazonaws.com \
  --set opensearch.port=443 \
  --set opensearch.auth.enabled=true
```

## Index Template

```json
{
  "index_patterns": ["eks-logs-*"],
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1
  },
  "mappings": {
    "properties": {
      "@timestamp": { "type": "date" },
      "kubernetes.pod_name": { "type": "keyword" },
      "kubernetes.namespace_name": { "type": "keyword" },
      "log": { "type": "text" },
      "level": { "type": "keyword" }
    }
  }
}
```

## Sample Dashboard Queries

### Error rate over time
```
{
  "aggs": {
    "time_buckets": {
      "date_histogram": {
        "field": "@timestamp",
        "fixed_interval": "5m"
      }
    }
  },
  "query": {
    "match": { "level": "ERROR" }
  }
}
```

### Top error sources
```
{
  "aggs": {
    "pod_names": {
      "terms": {
        "field": "kubernetes.pod_name",
        "size": 10
      }
    }
  },
  "query": {
    "match": { "level": "ERROR" }
  }
}
```

## References

- [OpenSearch](https://opensearch.org/)
- [EKS Workshop - OpenSearch](https://www.eksworkshop.com/docs/observability/opensearch/)