---
title: CronJobs — Time-Scheduled Workloads
tags: [kubernetes, workloads, cronjob, jobs, scheduling, batch, core-concepts]
date: 2026-06-07
description: The time-scheduled wrapper around Jobs. Cron syntax, time zones, concurrency policies, starting deadlines, suspend/resume, and when CronJob is enough vs when you need Airflow.
---

# CronJobs — Time-Scheduled Workloads

> https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/

A **CronJob** runs [[Kubernetes/concepts/L03-workloads/06-job|Jobs]] on a **time-based schedule**. Think of it as the k8s equivalent of `crontab(5)`: a schedule expression that says "create a Job at this time, with this template."

CronJob is a thin layer over Job:

```
CronJob
  │
  │ "every hour"
  ▼
Creates Job ──── creates Pods ──── runs to completion
  │
  │ Job is kept around for history
  ▼
After ttlSecondsAfterFinished, Job is GC'd
```

For simple "run X every Y" patterns, CronJob is the right answer. For DAG dependencies, backfills, retries across days, or SLA-based scheduling, reach for a workflow engine like Argo Workflows or Airflow.

## Table of Contents

1. [The CronJob Mental Model](#1-the-cronjob-mental-model)
2. [Manifest Anatomy](#2-manifest-anatomy)
3. [The Schedule Field — Cron Syntax](#3-the-schedule-field--cron-syntax)
4. [Time Zones](#4-time-zones)
5. [Concurrency Policies](#5-concurrency-policies)
6. [Starting Deadline Seconds](#6-starting-deadline-seconds)
7. [Suspend, Resume, and History Limits](#7-suspend-resume-and-history-limits)
8. [CronJob Lifecycle (Tick by Tick)](#8-cronjob-lifecycle-tick-by-tick)
9. [Patterns](#9-patterns)
10. [CronJob vs External Schedulers](#10-cronjob-vs-external-schedulers)
11. [Operational Recipes](#11-operational-recipes)
12. [Troubleshooting](#12-troubleshooting)
13. [Gotchas and Common Mistakes](#13-gotchas-and-common-mistakes)
14. [Related Notes](#14-related-notes)

---

## 1. The CronJob Mental Model

### The contract

> "At every scheduled time, create a Job from this template. Don't create overlapping Jobs (depending on the concurrency policy). Keep history of the last N Jobs. Allow the schedule to be paused."

A CronJob does not run Pods directly. It creates Jobs. The Jobs create Pods. The Pods run the workload.

### The clock

The schedule is evaluated by the **cronjob controller**, which runs in **kube-controller-manager** (not on the kubelet, not on a node). One controller instance is the leader at any time; if it crashes, another takes over.

Important: the controller evaluates the schedule against the **controller's clock** (typically UTC, set at controller startup). This is the clock that determines when Jobs are created.

### The state machine

```
            ┌────────────────────────────────────────┐
            │                                         │
            ▼                                         │
      ┌──────────┐                                   │
      │ Created  │                                   │
      └────┬─────┘                                   │
           │                                         │
           │ (next scheduled time)                   │
           ▼                                         │
      ┌──────────┐                                   │
      │ Schedule │──tick──▶ Create Job               │
      │ Triggered│                                   │
      └────┬─────┘                                   │
           │                                         │
           │ (concurrency policy applies)            │
           ├─ Allow ──▶ Job is created ──▶ next tick │
           │                                         │
           ├─ Forbid ──▶ if previous still active, skip this tick
           │                                         │
           └─ Replace ──▶ kill previous, start new
```

### What a CronJob does NOT do

| Capability | CronJob | Argo Workflows / Airflow |
|---|---|---|
| Run a Job on a schedule | ✅ | ✅ |
| DAG dependencies (B after A) | ❌ | ✅ |
| Backfills across missed days | ❌ | ✅ |
| Conditional execution | ❌ | ✅ |
| SLA-based scheduling | ❌ | ✅ |
| Cross-cluster scheduling | ❌ | ✅ (with effort) |
| Pause / resume schedule | ✅ (`suspend`) | ✅ |
| Per-run history | ✅ (configurable) | ✅ (richer) |

---

## 2. Manifest Anatomy

A minimum-viable CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello
spec:
  schedule: "* * * * *"           # every minute
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: hello
            image: busybox:1.36
            args: ["echo", "hello from cron"]
          restartPolicy: OnFailure
```

Full anatomy:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
  namespace: batch
  labels:
    app: backup
    tier: data
spec:
  schedule: "0 2 * * *"            # 02:00 every day
  timeZone: "Etc/UTC"               # k8s 1.25+
  startingDeadlineSeconds: 200      # see section 6
  concurrencyPolicy: Forbid         # see section 5
  suspend: false                    # see section 7
  successfulJobsHistoryLimit: 3     # see section 7
  failedJobsHistoryLimit: 1         # see section 7
  jobTemplate:                      # full Job spec
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 3600
      ttlSecondsAfterFinished: 86400
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: backup-runner
          containers:
          - name: backup
            image: myorg/backup:2.1
            command: ["./backup.sh"]
            env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: url
            resources:
              requests:
                cpu: 200m
                memory: 256Mi
              limits:
                cpu: 1
                memory: 1Gi
status:
  active:                          # currently-running Jobs created by this CronJob
  - apiVersion: batch/v1
    kind: Job
    name: db-backup-28532020
    namespace: batch
    resourceVersion: "12345"
    uid: abc-123
  lastScheduleTime: "2025-05-24T02:00:00Z"
  lastSuccessfulTime: "2025-05-24T02:00:30Z"
```

### Required fields

| Field | Required | Why |
|---|---|---|
| `apiVersion` | yes | Always `batch/v1` |
| `kind` | yes | Must be `CronJob` |
| `metadata.name` | yes | DNS-1123 label |
| `spec.schedule` | yes | Cron expression |
| `spec.jobTemplate` | yes | The Job template to instantiate |
| `spec.jobTemplate.spec.template.spec.restartPolicy` | yes (in template) | `OnFailure` or `Never` |

### `schedule` is required and immutable

You cannot change the `schedule` field on a CronJob after creation. The API server rejects the update. To change a schedule, you must delete and recreate the CronJob.

This is a known sharp edge. The community has discussed making it mutable, but as of k8s 1.30, it's immutable.

---

## 3. The Schedule Field — Cron Syntax

The `schedule` field uses standard cron syntax, with extensions for `@hourly` etc.

### The standard cron format

```
┌───────────── minute (0 - 59)
│ ┌───────────── hour (0 - 23)
│ │ ┌───────────── day of month (1 - 31)
│ │ │ ┌───────────── month (1 - 12)
│ │ │ │ ┌───────────── day of week (0 - 6) (Sunday = 0)
│ │ │ │ │
* * * * *
```

### Common expressions

| Expression | When |
|---|---|
| `* * * * *` | Every minute |
| `0 * * * *` | Every hour, on the hour |
| `0 0 * * *` | Every day at midnight |
| `0 2 * * *` | Every day at 02:00 |
| `0 0 * * 0` | Every Sunday at midnight |
| `0 0 1 * *` | First of the month at midnight |
| `*/5 * * * *` | Every 5 minutes |
| `0 9-17 * * 1-5` | Hourly from 9 AM to 5 PM, Mon-Fri |
| `0 0,12 * * *` | Daily at midnight and noon |
| `30 4 1,15 * *` | 04:30 on the 1st and 15th of every month |

### The `@` shortcuts

| Shortcut | Equivalent |
|---|---|
| `@hourly` | `0 * * * *` |
| `@daily` | `0 0 * * *` |
| `@midnight` | `0 0 * * *` |
| `@weekly` | `0 0 * * 0` |
| `@monthly` | `0 0 1 * *` |
| `@yearly` | `0 0 1 1 *` |
| `@annually` | `0 0 1 1 *` |

### Special characters

| Char | Meaning | Example |
|---|---|---|
| `*` | Any value | `*` in hour = any hour |
| `,` | Value list separator | `1,3,5` in day = 1st, 3rd, 5th |
| `-` | Range | `9-17` in hour = 9 AM to 5 PM |
| `/` | Step | `*/15` in minute = every 15 min |
| `?` | No specific value (some implementations) | k8s doesn't support this; use `*` |

### Two gotchas in cron syntax

1. **Day-of-month AND day-of-week are OR'd if both are restricted.** If you set both, the Job runs when **either** matches. To get "the 1st of every month AND Monday," you need a workaround (split into two CronJobs, or use a workflow engine).

2. **"Every minute" is `* * * * *`, not `*/1 * * * *`.** Both work, but the former is simpler.

### Validation

The schedule is validated at creation time. Invalid expressions are rejected with a clear error. You can't create a CronJob with a bad schedule.

To check the next 5 fire times of a cron expression without creating a CronJob:

```bash
# Using a Python one-liner
python3 -c "
from datetime import datetime, timedelta
import croniter
c = croniter('0 2 * * *', datetime.now())
for i in range(5):
    print(c.get_next(datetime))
"
```

Or use a tool like [crontab.guru](https://crontab.guru) for human-readable explanations.

---

## 4. Time Zones

`spec.timeZone` (k8s 1.25+) lets you specify a timezone:

```yaml
spec:
  schedule: "0 9 * * *"      # 09:00
  timeZone: "America/New_York"
```

This means: 09:00 New York time, every day. The schedule is evaluated in the specified timezone, not in the controller's timezone.

### Before k8s 1.25

The schedule was always interpreted in the controller's timezone, which is typically UTC. To get "9 AM Eastern Time," you'd compute the UTC equivalent:

- 9 AM ET (EST, UTC-5) = 14:00 UTC
- 9 AM ET (EDT, UTC-4) = 13:00 UTC

This breaks during DST transitions. Use `timeZone` to avoid the headache.

### The IANA timezone database

`timeZone` accepts any IANA timezone name:

| Region | Timezones |
|---|---|
| Americas | `America/New_York`, `America/Chicago`, `America/Denver`, `America/Los_Angeles`, `America/Sao_Paulo` |
| Europe | `Europe/London`, `Europe/Paris`, `Europe/Berlin`, `Europe/Moscow` |
| Asia | `Asia/Tokyo`, `Asia/Shanghai`, `Asia/Kolkata`, `Asia/Dubai` |
| Pacific | `Pacific/Auckland`, `Australia/Sydney` |
| UTC | `Etc/UTC` (alias for UTC, no DST) |

For full list, see the [IANA timezone database](https://www.iana.org/time-zones).

### DST and CronJob

CronJob does **not** handle DST transitions intelligently. From the official docs:

> "The controller does not synchronize the time zone, e.g. when a region permanently changes its time zone. To handle this, the user is expected to recreate the CronJob object."

This means: if Brazil ends DST and the country stays at UTC-3 forever, your CronJob will keep firing at the "old" UTC-3 time. You need to recreate it with the new offset.

In practice: pick `Etc/UTC` if you don't have a strong reason for local time, and let your application handle the conversion.

---

## 5. Concurrency Policies

What happens if a Job is still running when the next scheduled time arrives:

```yaml
spec:
  concurrencyPolicy: Forbid     # or Allow or Replace
```

| Policy | Behavior |
|---|---|
| `Allow` (default) | Overlapping Jobs are allowed. Multiple instances can run concurrently. |
| `Forbid` | Skip the new run if the previous one is still active. |
| `Replace` | Kill the previous Job's Pods and start the new one. |

### The decision matrix

| Use case | Recommended policy |
|---|---|
| **Database backups** | `Forbid` — don't run two backups against the same DB at once |
| **Log rotation** | `Forbid` — don't double-rotate |
| **Cache warmer** | `Replace` — you want the latest run |
| **Metric scrapers** | `Allow` — multiple instances are fine |
| **Data pipeline (independent runs)** | `Allow` — each run is independent |
| **Distributed ML training (resume from checkpoint)** | `Forbid` — don't step on the running training |

### `Forbid` and missed runs

With `Forbid`, if a scheduled time is skipped, the run is **lost**. The next scheduled time is the next slot. There is no catch-up.

Example: schedule is `0 * * * *` (every hour), `concurrencyPolicy: Forbid`. A run starts at 14:00 and runs until 15:30. The 15:00 run is skipped. The 16:00 run starts on time. The 15:00 run is **not** made up.

### `Replace` and `Forbid` are not the same

| | `Forbid` | `Replace` |
|---|---|---|
| Previous Job still running? | Skip new run | Kill previous, start new |
| Previous run is preserved? | Yes (continues) | No (terminated) |
| Use for | Sequential safety | Latest-wins |

`Replace` is the right policy for "I always want the most recent run" patterns. `Forbid` is the right policy for "don't run two of me at once."

### What "still active" means

A Job is "active" if it has any non-terminated Pod. Once all Pods have terminated (success or failure), the next scheduled time triggers a new Job.

For a Job with `restartPolicy: OnFailure` and a script that keeps failing and restarting, the Job can stay "active" indefinitely. `Forbid` will keep skipping new runs until the Job is deleted or completes.

---

## 6. Starting Deadline Seconds

`startingDeadlineSeconds` bounds the time between the scheduled time and the actual Job creation:

```yaml
spec:
  startingDeadlineSeconds: 200
```

If the controller can't create the Job within 200 seconds of the scheduled time, the run is **skipped**. The schedule continues normally from there.

### Why this matters

The controller-manager might be down (a leader election issue, a crash, a rolling update). When it comes back, it might be minutes or hours later. Without `startingDeadlineSeconds`, the controller would catch up on all missed runs, possibly creating dozens of Jobs in a burst.

With `startingDeadlineSeconds: 200`, the controller only creates a Job if it's "still relevant" (within the deadline). Missed runs are dropped.

### Choosing the value

| Pattern | Recommended value |
|---|---|
| **Every minute** | `60` (only create if within 1 minute) |
| **Every hour** | `300` (5 minutes) |
| **Daily at 02:00** | `3600` (1 hour) or more |
| **Once a month** | `86400` (1 day) |
| **Critical hourly backups** | `600` (10 minutes — you want a tighter bound) |

If you set it too high, the controller will queue up many missed runs. If too low, brief controller-manager restarts will drop runs.

### The behavior

```
Time 14:00:00  - scheduled
Time 14:00:05  - controller creates Job ✓ (within deadline)

Time 14:00:00  - scheduled
Time 14:00:30  - controller-manager is down
Time 14:05:00  - controller-manager comes back
               - startingDeadlineSeconds: 200
               - now > scheduled + 200s, so this run is SKIPPED
Time 15:00:00  - next scheduled time
Time 15:00:05  - controller creates Job ✓
```

### Important: no catch-up

Unlike some external schedulers, **CronJob does not compensate for missed runs**. If the controller was down for 3 hours and the schedule is hourly, those 3 runs are lost. The next scheduled time is the next one.

If you need reliable catch-up, use a workflow engine (Argo Workflows, Airflow) with explicit backfill support.

---

## 7. Suspend, Resume, and History Limits

### Suspend

Pause a CronJob from creating new Jobs:

```yaml
spec:
  suspend: true
```

The CronJob is "paused." No new Jobs are created. Existing Jobs are not affected. You can edit the CronJob to change its spec while suspended (e.g., update the image, change the schedule).

```bash
kubectl patch cronjob <name> -p '{"spec":{"suspend":true}}' --type=merge
```

This is the right way to:

- Disable a CronJob temporarily without deleting it (keeps history)
- Edit the CronJob's template safely
- Hold the schedule during maintenance

To resume:

```bash
kubectl patch cronjob <name> -p '{"spec":{"suspend":false}}' --type=merge
```

The next scheduled time after resume will trigger a Job.

### History limits

`successfulJobsHistoryLimit` and `failedJobsHistoryLimit` control how many finished Jobs are kept:

```yaml
spec:
  successfulJobsHistoryLimit: 3     # keep 3 most recent successful Jobs
  failedJobsHistoryLimit: 1         # keep 1 most recent failed Job
```

Default: 3 and 1.

When a new Job is created, the controller counts the existing finished Jobs (matching the CronJob's `ownerReference`). If the count exceeds the limit, the oldest are deleted.

Set these to 0 if you don't want any history (saves etcd space). For high-volume CronJobs (every minute, keeping 3 = 3 minutes of history), this matters.

### The etcd cost

Each Job creates Pods, which have status, events, and logs. With 1000 CronJobs each keeping 3 Jobs, you have 3000 Job objects in etcd. Each Job has 1+ Pod. That's thousands of objects, all with events.

For cost-sensitive clusters, set `successfulJobsHistoryLimit: 1` or `0` for high-frequency CronJobs.

### The cleanup mechanism

The CronJob controller doesn't directly delete the Job objects. It uses the same cascade mechanism as Pod garbage collection:

1. The CronJob is the owner of each Job it creates
2. When the count of owned Jobs exceeds the limit, the controller deletes the oldest
3. The Job's Pods are deleted via owner references

This is why the limits are enforced cleanly without a separate cleanup job.

---

## 8. CronJob Lifecycle (Tick by Tick)

What happens at every scheduled tick:

```
1. CronJob controller's informer fires (every minute by default)
2. Controller checks all CronJobs for due times
3. For each due CronJob:
   a. Check if suspended → if yes, skip
   b. Check if a previous Job is still active
      - If concurrencyPolicy=Forbid and previous active → skip
      - If concurrencyPolicy=Replace and previous active → delete previous
      - Otherwise → proceed
   c. Check if within startingDeadlineSeconds
      - If past deadline → skip (drop the missed run)
   d. Create the Job from jobTemplate
   e. Update CronJob status (lastScheduleTime, active)
4. Garbage-collect old Jobs based on history limits
5. Wait for next informer tick
```

The "tick" is the controller's reconciliation loop, which runs roughly every 10 seconds by default. So a CronJob with `* * * * *` (every minute) might fire up to 10 seconds after the scheduled time, depending on the controller's load.

### The naming convention

Each Job created by a CronJob is named:

```
<cronjob-name>-<unix-timestamp-of-creation>
```

For example, a `db-backup` CronJob that fires at 1700000000 will create `db-backup-1700000000`. This timestamp makes it easy to see when the Job ran.

The Job's `ownerReference` points to the CronJob, so when the CronJob is deleted, all its Jobs are deleted too.

### The status

```yaml
status:
  active:
  - apiVersion: batch/v1
    kind: Job
    name: db-backup-1700000000
    namespace: batch
  lastScheduleTime: "2025-05-24T02:00:00Z"
  lastSuccessfulTime: "2025-05-24T02:00:30Z"
```

`lastScheduleTime` is when the controller last created a Job. `lastSuccessfulTime` is when the most recent Job reached `Complete`.

If `lastScheduleTime` is updating but `lastSuccessfulTime` is not, the Jobs are being created but failing. Investigate.

---

## 9. Patterns

### Pattern 1: Database backup every night

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
spec:
  schedule: "0 2 * * *"
  timeZone: "Etc/UTC"
  startingDeadlineSeconds: 600
  concurrencyPolicy: Forbid        # don't run two backups at once
  successfulJobsHistoryLimit: 7    # keep a week of successful backups
  failedJobsHistoryLimit: 3        # keep 3 failures for debugging
  jobTemplate:
    spec:
      backoffLimit: 1              # don't retry failed backups
      activeDeadlineSeconds: 3600  # 1 hour max
      ttlSecondsAfterFinished: 604800  # delete Job after 7 days
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: backup-runner
          containers:
          - name: backup
            image: myorg/backup:2.1
            command: ["./backup.sh"]
            env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: url
            - name: BACKUP_BUCKET
              value: s3://myorg-db-backups/
            resources:
              requests:
                cpu: 500m
                memory: 512Mi
```

### Pattern 2: Cleanup job every hour

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup-stale-data
spec:
  schedule: "0 * * * *"           # top of every hour
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 3600
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: cleanup
            image: myorg/cleanup:1.0
            command: ["./cleanup", "--older-than=24h"]
```

### Pattern 3: ML training every Sunday at midnight

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: weekly-train
spec:
  schedule: "0 0 * * 0"            # Sunday midnight UTC
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 3600
  jobTemplate:
    spec:
      backoffLimit: 0              # no retries
      activeDeadlineSeconds: 21600  # 6 hours
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: train
            image: myorg/trainer:3.0
            command: ["./train", "--epochs=100"]
            resources:
              requests:
                nvidia.com/gpu: 1
                cpu: 4
                memory: 16Gi
              limits:
                nvidia.com/gpu: 1
                cpu: 8
                memory: 32Gi
```

### Pattern 4: Cache warmer every 10 minutes (Replace)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cache-warmer
spec:
  schedule: "*/10 * * * *"
  concurrencyPolicy: Replace      # always want the latest run
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 600
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: warmer
            image: myorg/warmer:1.0
            command: ["./warm"]
```

### Pattern 5: Heartbeat / canary (every minute, Allow)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: heartbeat
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Allow         # many can run concurrently; cheap
  successfulJobsHistoryLimit: 0    # no history needed
  failedJobsHistoryLimit: 1
  startingDeadlineSeconds: 60
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 60
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: heartbeat
            image: myorg/heartbeat:1.0
            command: ["./send-heartbeat"]
            resources:
              requests:
                cpu: 10m
                memory: 32Mi
              limits:
                cpu: 100m
                memory: 64Mi
```

### Pattern 6: Email digest every weekday at 8 AM

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-digest
spec:
  schedule: "0 8 * * 1-5"          # 8 AM, Mon-Fri
  timeZone: "America/New_York"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 86400
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: digest
            image: myorg/digest:1.0
            command: ["./send-digest"]
```

---

## 10. CronJob vs External Schedulers

### When CronJob is enough

- A single, time-based trigger
- No dependencies between Jobs
- Tolerable to miss runs during outages
- Small number of CronJobs (tens, not thousands)
- No need for backfill or catch-up

### When you need Argo Workflows

- DAG dependencies: "B runs after A succeeds, C runs after A and B"
- Conditional execution: "Run D only if X is true"
- Per-step resource allocation and parallelism
- Built-in retry, error handling, artifact passing
- Visual workflow UI

### When you need Airflow

- Backfills across days/weeks
- SLA-based scheduling with deadlines and alerts
- Cross-system dependencies (e.g., wait for an SFTP upload before processing)
- Mature operator ecosystem (S3, BigQuery, Snowflake, etc.)
- Compliance and audit requirements

### When you need neither

- **"Run X every Y" with no deps** → CronJob ✅
- **"Trigger from an event"** → use a webhook + Job, or a message queue + worker Deployment
- **"Continuous processing"** → use a Deployment, not a CronJob

### The decision tree

```
Need to run work on a schedule?
│
├── Single trigger, no deps? ──▶ CronJob
│
├── DAG dependencies? ──▶ Argo Workflows
│
├── Backfill / cross-system deps? ──▶ Airflow
│
├── Event-triggered? ──▶ webhook + Job, or message queue + worker
│
└── Continuous? ──▶ Deployment with worker pattern
```

---

## 11. Operational Recipes

### Recipe 1: Manually trigger a CronJob

```bash
# Create a Job from the CronJob's template, immediately
kubectl create job --from=cronjob/<cronjob-name> <manual-job-name>
```

This creates a one-off Job with the same template. The CronJob's schedule is not affected; the next scheduled time still runs.

### Recipe 2: List all Jobs created by a CronJob

```bash
kubectl get jobs -l batch.kubernetes.io/cronjob=<cronjob-name>
# or (older clusters):
kubectl get jobs -l job-name=<cronjob-name>
```

The label is `batch.kubernetes.io/cronjob` (k8s 1.27+) or `job-name` (older).

### Recipe 3: Get the last successful run

```bash
kubectl get cronjob <name> -o jsonpath='{.status.lastSuccessfulTime}'
```

### Recipe 4: Suspend all CronJobs in a namespace

```bash
kubectl get cronjob -n <namespace> -o name | \
  xargs -I {} kubectl patch {} -n <namespace> -p '{"spec":{"suspend":true}}' --type=merge
```

### Recipe 5: Check if a CronJob is firing

```bash
# Recent Job creations
kubectl get events -n <namespace> --field-selector involvedObject.kind=CronJob

# Or directly:
kubectl get cronjob <name> -o jsonpath='{.status.lastScheduleTime}'
```

If `lastScheduleTime` is recent, the controller is firing Jobs. If it's stale, the controller isn't firing — check controller-manager health.

### Recipe 6: Bulk-update image

```bash
# Update image on all CronJobs matching a label
kubectl get cronjob -A -l app=backup -o name | \
  xargs -I {} kubectl patch {} -p '{"spec":{"jobTemplate":{"spec":{"template":{"spec":{"containers":[{"name":"backup","image":"myorg/backup:2.2"}]}}}}}}' --type=merge
```

(Note: this is a deep patch. Verify the structure matches your CronJob.)

### Recipe 7: Disable a CronJob without deleting history

```bash
kubectl patch cronjob <name> -p '{"spec":{"suspend":true}}' --type=merge
```

The CronJob stays around (with its history). To re-enable:

```bash
kubectl patch cronjob <name> -p '{"spec":{"suspend":false}}' --type=merge
```

---

## 12. Troubleshooting

### Symptom: CronJob is not firing

**Check 1: Is it suspended?**

```bash
kubectl get cronjob <name> -o jsonpath='{.spec.suspend}'
# "true" = suspended
```

**Check 2: Is the schedule valid?**

The schedule was validated at creation, but if you copy-paste, double-check the syntax.

**Check 3: Is the controller-manager healthy?**

```bash
kubectl get pods -n kube-system -l component=kube-controller-manager
# All instances should be Running and Ready
```

**Check 4: Are there events for the CronJob?**

```bash
kubectl describe cronjob <name>
```

Look for events at the bottom. If the controller is firing, you'll see Job-creation events.

**Check 5: Is `lastScheduleTime` updating?**

```bash
kubectl get cronjob <name> -o jsonpath='{.status.lastScheduleTime}'
watch -n 30 'kubectl get cronjob <name> -o jsonpath="Last schedule: {.status.lastScheduleTime}\n"'
```

If it's not updating, the controller isn't firing.

### Symptom: CronJob fires but Jobs are failing

**Check 1: Look at the most recent Job**

```bash
# Find the latest Job
kubectl get jobs -l batch.kubernetes.io/cronjob=<name> --sort-by=.metadata.creationTimestamp -o name | tail -1

# Check its status
kubectl describe job <job-name>
kubectl logs -l job-name=<job-name> --tail=100
```

**Check 2: Are resources insufficient?**

Check if the Job's Pods are `Pending` due to resource pressure.

**Check 3: Is `backoffLimit` too low?**

A flaky script with `backoffLimit: 1` will fail fast. Raise it.

### Symptom: CronJob fires multiple times when it shouldn't

This usually means:

- `concurrencyPolicy: Allow` (default) — overlapping runs are intended
- The previous Job is failing silently and never reaches "not active" state

Check:

```bash
kubectl get jobs -l batch.kubernetes.io/cronjob=<name>
```

If you see many Jobs running concurrently, change to `Forbid` or `Replace`.

### Symptom: CronJob skipped a run

This is normal if:

- `concurrencyPolicy: Forbid` and the previous run was still active
- `startingDeadlineSeconds` was exceeded (controller was late)

To recover, manually trigger:

```bash
kubectl create job --from=cronjob/<name> <manual-name>
```

### Symptom: Time zone confusion

The CronJob fires at the wrong local time. Check:

1. Is `timeZone` set? If yes, that's your reference. If no, the controller's timezone is used.
2. Is the controller-manager's timezone UTC? (It usually is.)
3. Is the schedule interpreted correctly?

Convert your expected local time to UTC and verify against the actual fire times.

### Symptom: CronJob with `timeZone` doesn't work in older clusters

`spec.timeZone` was added in k8s 1.25. In older clusters, the field is silently ignored. Check the cluster version:

```bash
kubectl version
```

If < 1.25, use UTC and convert in your application or the schedule.

### Symptom: Jobs are not being garbage-collected

The history limits are not being enforced. Check:

- Is the CronJob's `successfulJobsHistoryLimit` / `failedJobsHistoryLimit` set?
- Is the controller running?
- Is the Job owned by this CronJob? (Check `ownerReference`)

If the Job was created manually (not by the CronJob), the GC won't touch it.

---

## 13. Gotchas and Common Mistakes

### Schedule gotchas

- **`schedule` is immutable.** You cannot change it. Delete and recreate.
- **CronJob does not catch up on missed runs.** If the controller is down, those runs are lost.
- **Day-of-month and day-of-week are OR'd.** You can't say "1st of the month AND Monday" in one expression.
- **`timeZone` is silently ignored on clusters < 1.25.**

### Concurrency gotchas

- **Default `concurrencyPolicy: Allow` allows overlapping runs.** Often not what you want.
- **`Forbid` skips silently.** If you don't monitor `lastScheduleTime`, you won't notice missed runs.
- **`Replace` kills the previous run.** If the previous run had side effects (e.g., wrote to a database), those side effects are interrupted.

### Deadline gotchas

- **`startingDeadlineSeconds: null` (default) is unlimited.** A controller that comes back from a 1-day outage will try to fire all 1440 missed runs.
- **Always set `startingDeadlineSeconds`** to bound the catch-up window.

### History gotchas

- **Default `successfulJobsHistoryLimit: 3` may not be enough** for high-frequency CronJobs.
- **Each retained Job keeps its Pods and events.** This adds up fast.
- **For high-frequency CronJobs (every minute), set limits to 0 or 1.**

### Suspend gotchas

- **Suspending does not delete existing Jobs.** If a Job is running and you suspend the CronJob, the Job continues.
- **Suspending is not a "pause" for the next tick.** The schedule is paused; existing activity is unaffected.

### Naming gotchas

- **Job names are `<cronjob-name>-<unix-timestamp>`.** If you create a Job manually with the same name as one the CronJob would create, the CronJob's creation will fail (duplicate name).
- **CronJob names must be DNS-1123 compatible.** Lowercase, ≤52 chars, no underscores.

### Concurrency vs. startup ordering

When the controller creates a Job, the Job creates a Pod. The Pod takes time to start. If the next scheduled time is 1 second later, you could have two Jobs running in the same second.

This is fine if `concurrencyPolicy: Allow`. With `Forbid` or `Replace`, the controller checks "is there an active Job" before creating a new one. The "active" check is by Job name, not by Pod phase, so a Job with `restartPolicy: OnFailure` and many in-place container restarts is still "active."

### Other gotchas

- **The controller evaluates the schedule in `timeZone` (or UTC if not set).** It does not use the cluster's local time.
- **CronJob does not respect NTP slew or DST.** Time changes are not handled gracefully.
- **A CronJob with `suspend: true` from creation is never started.** Setting it later in the lifecycle has no effect on already-created Jobs.
- **CronJob is namespace-scoped.** To run cluster-wide, you need a CronJob in each namespace (or use a privileged operator).
- **No built-in alerting.** Use the `lastScheduleTime` / `lastSuccessfulTime` status with your monitoring system to alert on missed runs.

---

## 14. Related Notes

| Topic | Note |
|---|---|
| Jobs (what CronJob creates) | [[Kubernetes/concepts/L03-workloads/06-job\|06 — Job]] |
| Pods (what Jobs run) | [[Kubernetes/concepts/L03-workloads/01-pods\|01 — Pods]] |
| Deployment (long-running) | [[Kubernetes/concepts/L03-workloads/03-deployments\|03 — Deployments]] |
| Init containers (run before app) | [[Kubernetes/concepts/L03-workloads/08-init-containers\|08 — Init Containers]] |
| Resource requests and limits | [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|L06 — Resource Requests and Limits]] |
| Taints and tolerations | [[Kubernetes/concepts/L06-scheduling-scaling\|L06 — Scheduling and Scaling]] |
| Garbage collection (TTL, history) | [[Kubernetes/concepts/L09-advanced/06-garbage-collection\|L09 — Garbage Collection]] |
