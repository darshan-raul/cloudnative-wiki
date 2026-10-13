---
title: CloudWatch Logs Insights
description: CloudWatch Logs Insights — powerful log query language for CloudWatch Logs. Query syntax, saved queries, contribution insights, and integration with dashboards.
tags:
  - aws/monitoring
date: 2026-10-12
---

# CloudWatch Logs Insights

Prerequisites: [[AWS/security/iam/README|scoped IAM access]] and [[AWS/monitoring/README|telemetry, SLI and retention design]].

Logs Insights queries CloudWatch Logs. Contributor Insights identifies heavy contributors using rules; these are different APIs, schemas and billing dimensions.

## Query language and fixture

These examples use Logs Insights QL, not SQL or PPL. First ingest the structured fixture in [[AWS/monitoring/cloudwatch-logs/README|the Logs lab]], including status and durationMs fields. `@timestamp` is event time; `@ingestionTime` is ingestion time.

```text
fields @timestamp, @ingestionTime, service, status, durationMs
| filter service = "demo"
| stats count(*) as requests, pct(durationMs, 95) as p95 by bin(5m)
| sort p95 desc
```

Expected: a bucket containing the fixture and p95 near 120. To find top source IPs in a dataset that actually contains src_ip, use:

```text
stats count(*) as requests by src_ip
| sort requests desc
| limit 10
```

Do not sort an undefined count or copy generic percentile()/distinct()/fill() functions into QL. A language switch requires that language's syntax.

## API workflow

With logs StartQuery/GetQueryResults/StopQuery permissions scoped to the selected groups:

```bash
aws logs start-query --log-group-name /wiki-lab/demo \
  --start-time 1791763200 --end-time 1791849600 \
  --query-string 'fields @timestamp, status | filter status = 500 | limit 10'
```

Replace epoch seconds with the actual fixture interval. Save the returned queryId; poll `aws logs get-query-results --query-id QUERY_ID` with bounded backoff. Handle Complete, Failed, Cancelled and Timeout explicitly; call stop-query on abandonment. The correct namespace is logs, not a fictional `aws insights`. Saved queries use put-query-definition.

Contributor Insights uses CloudWatch put-insight-rule with a rule-definition schema; Logs QL cannot be pasted as a rule. Select a documented rule template, limit contributors/cardinality and test it with non-sensitive fixtures.

## Cost, failure and cleanup

Logs Insights charges for scanned data, not a fixed price per query. Restrict log groups/time ranges and understand class/index feature availability. Contributor Insights has rule/event costs. Treat absent fields as a dataset/schema issue; authorization or KMS failures require scoped policy diagnosis.

Stop unfinished queries, remove temporary query definitions/rules if created, and delete only the disposable source log group after investigation. Production retention policy belongs to compliance owners.

## Structured fixture and command catalogue

Use records containing service, status, durationMs and requestId. Add synthetic src_ip/username/queryMs fields only for exercises needing them; absent fields are not silently meaningful zeros.

| Command    | Role                               | Example boundary                                 |
| ---------- | ---------------------------------- | ------------------------------------------------ |
| fields     | Select/compute visible fields      | Does not filter all missing fields automatically |
| filter     | Restrict matching events           | String/numeric types matter                      |
| parse      | Extract from structured/plain text | Test the exact message format                    |
| stats      | Aggregate by keys/time buckets     | Produces a new result schema                     |
| sort/limit | Order/restrict result rows         | Use named post-stats columns                     |
| display    | Select final columns               | Different from ingestion schema                  |

## Operational QL recipes

Error counts by five-minute window:

```text
filter status >= 500
| stats count(*) as errors by bin(5m)
```

For an error **rate**, aggregate total and errors over the same population; an error count alone is not a percentage. Retrieve the denominator over the same interval/groups with this second query, then divide matching bucket counts in the investigation worksheet:

```text
stats count(*) as requests by bin(5m)
```

Latency uses the numeric durationMs field:

```text
stats avg(durationMs) as mean, pct(durationMs, 50) as p50, pct(durationMs, 95) as p95, pct(durationMs, 99) as p99 by service
| sort p99 desc
```

For a log message with a known plaintext shape, parse explicitly:

```text
fields @message
| parse @message "login user=* outcome=*" as username, outcome
| filter outcome = "denied"
| stats count(*) as denied by username
| sort denied desc
| limit 10
```

These are Logs Insights QL, not SQL/PPL. A query expecting JSON automatically discovered fields must be tested against actual log events/classes. Use documented functions such as pct(); validate every expression against the chosen language.

## Saved queries and asynchronous execution

```bash
aws logs put-query-definition --name wiki-lab-errors \
  --log-group-names /wiki-lab/demo \
  --query-string 'fields @timestamp, status | filter status >= 500 | limit 20'
```

Record queryDefinitionId for scoped deletion. Start-query returns a query ID; get-query-results may return partial results before Complete. Use bounded polling/timeout and stop-query on abandonment. Empty results may reflect the wrong time window/group/schema rather than a healthy application.

Dashboard query widgets need the appropriate language/source selection and permissions. Query refresh rescans data; a frequently refreshed dashboard can cost more than one investigation query.

## Contributor Insights and triage

Contributor Insights uses a rule-definition JSON schema under CloudWatch put-insight-rule, not a Logs QL string. Select a maintained rule template for the actual structured fields, define aggregate/count and matched events, then verify a known fixture contributor. Rules and matched-event charges differ from Logs scanned-byte pricing.

During an incident narrow time/group scope, examine @timestamp versus @ingestionTime, correlate request IDs and export only approved evidence. Cancel unfinished queries, delete lab query definitions/rules and restore dashboard refresh settings.

References: [QL commands](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html), [stats](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax-Stats.html), [saved-query API](https://docs.aws.amazon.com/cli/latest/reference/logs/put-query-definition.html), [Contributor rule syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContributorInsights-RuleSyntax.html).

## References

- [QL stats functions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax-Stats.html)
- [Discovered fields](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_AnalyzeLogData-discoverable-fields.html)
- [StartQuery](https://docs.aws.amazon.com/cli/latest/reference/logs/start-query.html)
- [Saved queries](https://docs.aws.amazon.com/cli/latest/reference/logs/put-query-definition.html)
- [Contributor rules](https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/put-insight-rule.html)
- [Pricing](https://aws.amazon.com/cloudwatch/pricing/)
