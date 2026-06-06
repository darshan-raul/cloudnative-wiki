---
title: CloudWatch Logs Insights
description: CloudWatch Logs Insights — powerful log query language for CloudWatch Logs. Query syntax, saved queries, contribution insights, and integration with dashboards.
tags:
  - aws
  - monitoring
  - logs
  - insights
  - cloudwatch
---

# CloudWatch Logs Insights

CloudWatch Logs Insights (CLI: `aws insights`) is a query language for analyzing CloudWatch Logs. It supports structured field extraction, aggregation, filtering, and visualization.

## Core Concepts

### Query Syntax

Logs Insights uses a SQL-like query language:

```sql
fields @timestamp, @message, level
| filter level = "ERROR"
| sort @timestamp desc
| limit 20
```

### Query Structure

```
fields        → Extract specific fields
| filter      → Filter log lines by condition
| sort         → Order by field
| limit        → Limit results
| stats        → Aggregate (count, avg, sum, etc.)
| display      → Rename fields for output
```

### Log Format Example (JSON)

```json
{"timestamp":"2024-01-15T10:30:00Z","level":"ERROR","service":"checkout","message":"Database connection failed","error":"Connection refused","duration_ms":5000}
```

Query:
```sql
fields @timestamp, service, message, duration_ms
| filter level = "ERROR"
| sort duration_ms desc
| limit 10
```

## Field Reference

| Field | Description |
|-------|-------------|
| `@timestamp` | When the log event was ingested |
| `@ingestionTime` | When CloudWatch received the log |
| `@message` | The raw log message (string) |
| `@log` | Full log group/stream path |
| `@logStream` | The log stream name |

## Query Commands

### fields — Extract Fields

```sql
fields @timestamp, @message, level, service
```

### filter — Filter by Condition

```sql
fields @timestamp, @message
| filter level = "ERROR"
| filter service = "checkout"
```

Filter operators:
- `=` `!=` `>=` `<=` `>` `<`
- `like` `not like` (regex)
- `contains` `not contains`
- `and` `or` `not`

```sql
fields @timestamp, @message
| filter level = "ERROR" and (service = "checkout" or service = "payment")
```

### stats — Aggregation

```sql
fields @timestamp, service, latency_ms
| filter service = "api"
| stats avg(latency_ms) as avg_latency,
       max(latency_ms) as max_latency,
       count() as request_count
       by service
| sort avg_latency desc
```

Aggregation functions:
- `count()` — number of log lines
- `avg()` `min()` `max()` `sum()`
- `percentile()` `distinct()`
- `sort asc/desc`

### sort and limit

```sql
fields @timestamp, @message
| filter level = "ERROR"
| sort @timestamp desc
| limit 50
```

## Common Query Patterns

### Error Rate Over Time

```sql
fields @timestamp, level
| filter level = "ERROR"
| stats count() as error_count
       by bin(5m)
| sort bin(5m) asc
```

### HTTP Request Latency Percentiles

```sql
fields @message
| filter @message like /GET|POST|PUT|DELETE/
| parse @message "* [*] *" as method, path, status
| stats avg(latency_ms) as p50,
       percentile(latency_ms, 95) as p95,
       percentile(latency_ms, 99) as p99
       by service
```

### Database Query Analysis

```sql
fields @timestamp, query, duration_ms
| filter type = "db.query"
| stats avg(duration_ms) as avg_query_time,
       max(duration_ms) as max_query_time,
       count() as query_count
       by query
| sort avg_query_time desc
| limit 20
```

### Failed Logins

```sql
fields @timestamp, src_ip, user, result
| filter event = "login" and result = "FAILED"
| stats count() as failed_attempts
       by src_ip, user
| sort failed_attempts desc
| limit 10
```

### Parse JSON Logs

```sql
fields @message
| filter @message like /\{.*\}/
| parse @message '{"timestamp":"*","level":"*","service":"*","message":"*"}' as ts, level, service, message
| filter level = "ERROR"
| sort @timestamp desc
```

## Saved Queries

Save frequently-used queries for reuse:

```bash
aws insights save-query \
  --name "errors-last-hour" \
  --query-string "fields @timestamp, @message | filter level = \"ERROR\" | sort @timestamp desc | limit 50" \
  --log-group-name /aws/lambda/my-function
```

Run a saved query:

```bash
aws insights start-query \
  --log-group-name /aws/lambda/my-function \
  --start-time 1705312800 \
  --end-time 1705316400 \
  --query-string "fields @timestamp, @message | filter level = \"ERROR\" | sort @timestamp desc"
```

## Contribution Insights

Contributor Insights identifies top contributors to a metric:

```sql
fields src_ip
| filter status = 500
| sort count() desc
| limit 10
```

### Creating a Contributor Insight Rule

```bash
aws insights put-insight-rules \
  --insight-rules '[{
    "Name": "top-500-errors",
    "Schema": {
      "Name": "CloudWatchLogInsightsRule",
      "MatchLogic": "And",
      "Constraints": [{
        "Dimensions": ["src_ip", "uri"],
        "Type": "string"
      }]
    },
    "FilterPattern": "{\"status\": [500]}",
    "ReleaseBehind": "LatestRelease"
  }]'
```

## Integration with Dashboards

Add Logs Insights queries to CloudWatch Dashboards:

```json
{
  "type": "logInsights",
  "x": 0, "y": 0, "width": 24, "height": 9,
  "properties": {
    "title": "Error Rate",
    "logGroupNames": ["/aws/lambda/checkout", "/aws/lambda/payment"],
    "queries": [
      {
        "text": "fields @timestamp, level | filter level = \"ERROR\" | stats count() by bin(5m)",
        "name": "Error Rate",
        "visible": true
      }
    ]
  }
}
```

## Visualization

Insights results can be displayed as:
- **Table** — Default, rows and columns
- **Line chart** — Time series (when using `bin()`)
- **Bar chart** — Aggregation by category
- **Pie chart** — Percentage breakdown

## Limits

| Resource | Limit |
|----------|-------|
| Query runtime | 60 minutes (async) |
| Results returned | 1,000 lines (sync), 10,000 (async) |
| Queries per account (concurrent) | 10 |
| Saved queries per account | 500 |

## References

- **Homepage:** https://aws.amazon.com/cloudwatch/
- **Documentation:** https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/
- **Pricing:** https://aws.amazon.com/cloudwatch/pricing/

## Pricing Examples

**Scenario 1:** A developer running 20 Logs Insights queries per day to debug production issues. 20 × 30 = 600 queries/month. Logs Insights: $0.005/query × 600 = $3/month. Without Logs Insights, debugging would require SSH into instances and running grep — 30 minutes/day × $50/hr = $1,500/month in engineering time.

**Scenario 2:** A security team using Contributor Insights to identify top IPs hitting 500 errors. One Contributor Insight rule running continuously. $0.10/million events ingested. 10M log events/month × $0.10/million = $1/month. Identifies a DDoS attack that would have caused $10,000 in downtime costs.

## Nuggets & Gotchas

- **Logs Insights queries are not real-time — they query historical data:** A query on the last 5 minutes of logs has a latency of 10-30 seconds. For real-time log analysis, use CloudWatch Contributor Insights or a third-party tool.
- **The `parse` command is powerful but slow on large log groups:** If your query times out, simplify the parse pattern or narrow the time range. Complex parse patterns with multiple regex groups are expensive.
- **Queries with `*` in field names are treated as glob, not regex:** If you have a field named `host.name` and you use `fields host.*`, it returns all fields starting with `host.`. If you want regex, use `fields regex "host\\..*"`.
- **The `bin()` function requires the time series to have at least one data point per bin:** If you bin by 5 minutes but your log group has no events in a 5-minute window, that bin is empty and doesn't appear in the chart. Use `stats` with `fill()` to handle gaps.
- **Query results are limited to 1,000 rows in the console (10,000 via API):** For large-scale log analysis, use async query execution (`aws insights start-query`) which can return up to 10,000 rows and stores results for 30 minutes.