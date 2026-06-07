---
title: Jobs — Run-to-Completion Workloads
tags: [kubernetes, workloads, jobs, batch, controllers, core-concepts]
date: 2026-06-07
description: The controller that runs Pods to completion. Completion modes, parallelism patterns, backoffLimit, indexed jobs, and the failure modes that make Jobs the right answer for batch processing.
---

# Jobs — Run-to-Completion Workloads

> https://kubernetes.io/docs/concepts/workloads/controllers/job/

A **Job** runs **one or more Pods to completion** — a workload that you want to **finish**, not run forever. The controller ensures a specified number of Pods terminate successfully. If a Pod fails, the Job controller creates a new one (subject to `backoffLimit`) until the desired number of completions is reached.

In other controllers, Pod termination is a **failure** (Deployment, StatefulSet). In a Job, Pod termination is the **goal**. The whole point of a Job is for the Pod to run, do its work, and exit.

A Job is the right answer for:

- Batch processing: video transcoding, image resizing, report generation
- One-shot data migrations
- Database schema migrations (with care)
- ML training jobs
- Anything you'd otherwise run from `cron` on a single machine

A Job is the **wrong** answer for long-running services (use a Deployment), per-node agents (use a DaemonSet), or scheduled recurring tasks (use a CronJob).

## Table of Contents

1. [The Job Mental Model](#1-the-job-mental-model)
2. [Manifest Anatomy](#2-manifest-anatomy)
3. [The Three Core Fields: Completions, Parallelism, BackoffLimit](#3-the-three-core-fields-completions-parallelism-backofflimit)
4. [Restart Policies in Jobs](#4-restart-policies-in-jobs)
5. [Pod Failure Handling and Backoff](#5-pod-failure-handling-and-backoff)
6. [Completion Modes: NonIndexed vs Indexed](#6-completion-modes-nonindexed-vs-indexed)
7. [Patterns](#7-patterns)
8. [Suspend, Resume, and TTL](#8-suspend-resume-and-ttl)
9. [Active Deadline — Bounding Job Runtime](#9-active-deadline--bounding-job-runtime)
10. [Job and Pod Lifecycle Integration](#10-job-and-pod-lifecycle-integration)
11. [Operational Recipes](#11-operational-recipes)
12. [Troubleshooting](#12-troubleshooting)
13. [Gotchas and Common Mistakes](#13-gotchas-and-common-mistakes)
14. [Related Notes](#14-related-notes)

---

## 1. The Job Mental Model

### The contract

> "Ensure `completions` Pods terminate successfully. If a Pod fails, replace it. Stop after `backoffLimit` retries. Bound the runtime by `activeDeadlineSeconds`."

A Job is a one-shot. Once it reaches its target number of successful completions, it's **done**. The Job object stays around (subject to `ttlSecondsAfterFinished`), but no new Pods are created.

### The state machine

```
┌─────────┐
│ Created │  (Job object exists, no Pods yet)
└────┬────┘
     │ controller creates first Pod
     ▼
┌─────────┐
│ Running │  (Pods running, may have failures)
└────┬────┘
     │
     ├── all completions succeed ──▶ Complete
     │
     ├── backoffLimit exceeded ──▶ Failed
     │
     └── activeDeadline exceeded ──▶ Failed (timeout)
```

The Job's `status.conditions` reflects the state:

| Condition | Meaning |
|---|---|
| `Complete` | All `completions` succeeded |
| `Failed` | `backoffLimit` reached OR `activeDeadlineSeconds` exceeded |

### What a Job does NOT do

| Capability | Job | CronJob | Deployment |
|---|---|---|---|
| Run to completion | ✅ | ✅ (via Job) | ❌ |
| Schedule | ❌ | ✅ | ❌ |
| Run forever (long-lived) | ❌ | ❌ | ✅ |
| Rollback | ❌ | ❌ | ✅ |
| Pause / resume | ✅ (`suspend`) | ✅ (`suspend`) | ✅ |
| Indexed work assignment (k8s 1.21+) | ✅ | ❌ | ❌ |

A Job is "do this work, exactly N times successfully, then stop." A Deployment is "keep N copies running, forever." A CronJob is "create Jobs on a schedule."

---

## 2. Manifest Anatomy

A minimum-viable Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: hello
spec:
  template:
    spec:
      containers:
      - name: hello
        image: busybox:1.36
        command: ["echo", "hello world"]
      restartPolicy: OnFailure    # required for Jobs (or Never)
```

Full anatomy:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: data-processor
  namespace: batch
  labels:
    app: data-processor
spec:
  completions: 10              # total successful Pods required
  parallelism: 3               # max running at once
  completionMode: NonIndexed   # or Indexed
  backoffLimit: 4              # retries before marking failed
  activeDeadlineSeconds: 3600  # max runtime
  ttlSecondsAfterFinished: 600 # auto-delete Job 10 min after completion
  suspend: false               # pause/resume
  selector:                    # auto-generated if omitted
    matchLabels:
      controller-uid: <uid>
  manualSelector: false        # true = you provide selector (advanced)
  template:
    metadata:
      labels:
        app: data-processor    # Job adds controller-uid label
    spec:
      restartPolicy: OnFailure # required: OnFailure or Never
      activeDeadlineSeconds: 3600  # per-Pod deadline
      backoffLimit: 4          # per-Pod retry limit
      serviceAccountName: data-processor-sa
      containers:
      - name: processor
        image: myorg/processor:2.1
        env:
        - name: JOB_COMPLETION_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 2
            memory: 2Gi
status:
  active: 3                    # currently running Pods
  succeeded: 7                 # total successful completions
  failed: 0                    # total failed Pods
  startTime: "2025-05-24T10:00:00Z"
  completionTime: "2025-05-24T10:15:00Z"
  conditions:
  - type: Complete
    status: "True"
    lastProbeTime: "2025-05-24T10:15:00Z"
  - type: JobFailure
    status: "False"
```

### Required fields

| Field | Required | Why |
|---|---|---|
| `apiVersion` | yes | Always `batch/v1` |
| `kind` | yes | Must be `Job` |
| `metadata.name` | yes | DNS-1123 label |
| `spec.template` | yes | Pod spec |
| `spec.template.spec.restartPolicy` | yes (in template) | Must be `OnFailure` or `Never`. **Never `Always`.** |

### The `restartPolicy` constraint

A Job's Pod template **must** have `restartPolicy: OnFailure` or `restartPolicy: Never`. The API server rejects any other value.

| `restartPolicy` | Behavior |
|---|---|
| `OnFailure` | Failed container is restarted **in place** (same Pod, same UID). Useful for transient errors. |
| `Never` | Failed Pod is left for you to inspect. A **new** Pod is created. Useful for debugging. |
| `Always` | **Rejected by the API server.** A Job is supposed to terminate. |

For most workloads, `OnFailure` is the right choice. `Never` is useful when you want to inspect the failed Pod before the next attempt.

---

## 3. The Three Core Fields: Completions, Parallelism, BackoffLimit

These three fields control how a Job runs. Get them wrong and the Job doesn't do what you expect.

### `completions`

The total number of **successful** Pods required for the Job to be Complete.

| Value | Meaning |
|---|---|
| `completions: 1` | Run one Pod, succeed once, Job is done. Most common for one-shot tasks. |
| `completions: 10` | Run 10 successful Pods. The controller creates Pods until 10 succeed. |
| `completions: null` | Special case: with `parallelism > 0` and `completionMode: NonIndexed`, this is a "one Pod at a time" pattern. The Job runs forever (no termination condition). |
| Omitted | Defaults to 1. |

### `parallelism`

The maximum number of Pods that may run **at the same time**.

| Value | Meaning |
|---|---|
| `parallelism: 1` | Sequential. One Pod at a time, wait for it to finish, then the next. |
| `parallelism: 3` | Up to 3 Pods running concurrently. |
| `parallelism: null` | Defaults to 1. |
| `parallelism: 0` | **Suspended.** No new Pods are created, but the Job is still tracked. |

### The combinator matrix

| `completions` | `parallelism` | Behavior |
|---|---|---|
| 1 | 1 | One Pod, run it, Job done. The simple case. |
| 10 | 1 | Sequential. One at a time, total 10. Slow but deterministic. |
| 10 | 5 | Two batches of 5 concurrent. Total wall time is roughly 2× one batch. |
| 10 | 10 | All 10 in parallel. Fastest, but heaviest load. |
| 10 | 0 | Suspended. No Pods run until you set `parallelism > 0` or remove it. |
| null | 5 | Run 5 Pods in parallel, never complete. The Job runs forever (until you delete it). |
| 10 | null | Defaults parallelism to 1. Sequential. |

### The classic "fan-out" pattern

10,000 files to process, 10 workers:

```yaml
spec:
  completions: 10            # actually... we use Indexed for this
  parallelism: 10
  completionMode: Indexed
```

For "10,000 files, 10 workers, work-stealing queue" you'd need an external work queue. A Job doesn't natively support work distribution without `Indexed` (see section 6) or a custom controller.

### `backoffLimit`

The number of times a Pod is **retried** before the Job is marked Failed.

| Value | Meaning |
|---|---|
| `backoffLimit: 4` | Default. After 4 failed Pods (4 different attempts), the Job is Failed. |
| `backoffLimit: 0` | No retries. Any failure fails the Job. |
| `backoffLimit: 100` | Tolerate 100 failures. Useful for flaky networks. |

A "failure" is a Pod that exits non-zero (with `restartPolicy: Never`) or a Pod that the kubelet restarted too many times (with `restartPolicy: OnFailure` — counts as 1 failure per restart cycle, capped by `backoffLimit`).

The default is 6 in older clusters, 4 in modern clusters. Always set it explicitly.

### The exponential backoff

Between retries, the Job controller waits with exponential backoff. The first retry is delayed by 10s, the second by 20s, then 40s, 80s, 160s, 300s (cap). So a flaky Job that hits `backoffLimit: 4` can take up to ~10 minutes before it's marked Failed.

If you need faster failure, set `backoffLimit: 1` (1 retry) or `backoffLimit: 0` (no retries).

---

## 4. Restart Policies in Jobs

The Pod template's `restartPolicy` is critical for Jobs:

### `OnFailure` (the default for most Jobs)

```yaml
spec:
  template:
    spec:
      restartPolicy: OnFailure
```

- The container exits with non-zero
- kubelet restarts the **container in place** (same Pod, same UID, same log)
- This counts as 1 retry toward `backoffLimit`
- Useful for: scripts that crash on transient errors (DB unavailable, network blip)

The Pod object is **not deleted** between retries. Logs accumulate in the same Pod, and you can see all retries in `kubectl logs <pod>`.

### `Never`

```yaml
spec:
  template:
    spec:
      restartPolicy: Never
```

- The container exits with non-zero
- The Pod is **left for you to inspect** (`kubectl describe pod`, `kubectl logs`)
- The Job controller creates a **new Pod** (new UID, new name) to retry
- Each attempt is a separate Pod; you can see them all in `kubectl get pods -l job-name=...`

Use this when:

- The failure is hard to reproduce and you need forensic data
- You're debugging a script and want to inspect each failed run
- The script has side effects you don't want to repeat

### `Always`

**Rejected by the API server.** A Job is supposed to terminate; `Always` would mean the Pod restarts forever, contradicting the Job's contract.

---

## 5. Pod Failure Handling and Backoff

When a Pod fails, the Job controller:

1. Increments the failure count
2. Computes the backoff time: `min(10s × 2^(failures-1), 300s)` after the first failure, then `min(10s × 2^(failures), 600s)` for subsequent failures
3. If `failures < backoffLimit`: create a new Pod (or wait for the in-place container restart with `OnFailure`)
4. If `failures >= backoffLimit`: mark the Job as Failed

### The exact backoff timing

| Failure # | Wait before next attempt |
|---|---|
| 1 | 10s |
| 2 | 20s |
| 3 | 40s |
| 4 | 80s |
| 5 | 160s |
| 6 | 300s |
| 7+ | 600s (cap) |

So a Job with `backoffLimit: 4` can take up to ~2.5 minutes of backoff time before failing.

### The `failed` status

```yaml
status:
  failed: 2
  conditions:
  - type: JobFailure
    status: "True"
    reason: BackoffLimitExceeded
    message: "Job has reached the specified backoff limit"
```

When `JobFailure: True`, the Job is not retried. It is permanently failed. To retry, delete the Job and create a new one (or use a CronJob that creates a new Job on each schedule).

### Failure modes that don't count

Some Pod terminations don't count toward `backoffLimit`:

- **Pod evicted due to node pressure** — the Pod is gone, but the eviction is not a "failure." The Job controller creates a new Pod.
- **Pod preempted by a higher-priority Pod** — same, no failure counted.
- **Pod deleted manually** — `kubectl delete pod` is treated as an eviction, not a failure.

If you want to count these, use `restartPolicy: Never` and design your script to exit with a non-zero code on actual failures only.

---

## 6. Completion Modes: NonIndexed vs Indexed

### `NonIndexed` (default)

Each Pod is interchangeable. The controller doesn't assign indices. The Job is Complete when `completions` Pods have succeeded, in any order.

```yaml
spec:
  completionMode: NonIndexed
  completions: 10
  parallelism: 3
```

Use when: each Pod does a unit of work, and you don't care which Pod does which unit. Example: processing items in an external queue.

### `Indexed` (k8s 1.21+)

Each Pod is assigned a **unique index** from 0 to `completions - 1`. The index is available in the Pod as the `JOB_COMPLETION_INDEX` environment variable.

```yaml
spec:
  completionMode: Indexed
  completions: 10
  parallelism: 3
```

The Pods get:
- `JOB_COMPLETION_INDEX=0` ... `JOB_COMPLETION_INDEX=9`
- Annotation: `batch.kubernetes.io/job-completion-index: "0"` ... `9`

The Job is Complete when **all** indices (0 through `completions - 1`) have a successful Pod.

### When to use Indexed

Indexed is the right answer when:

- **The work is pre-partitioned** — e.g., 10 shards of a database, and Pod 0 processes shard 0
- **You need a 1:1 mapping between Pod and work unit** — e.g., 10 model replicas, each trains on a different data slice
- **The work is determined at Job creation time** — e.g., "process these 100 named files"

Example: a database migration with 10 shards:

```yaml
spec:
  completionMode: Indexed
  completions: 10
  parallelism: 5
  template:
    spec:
      containers:
      - name: migrate-shard
        image: myorg/migrator:1.0
        command: ["./migrate", "--shard=$(JOB_COMPLETION_INDEX)"]
        env:
        - name: JOB_COMPLETION_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
```

### NonIndexed with `completions: null`

If `completionMode: NonIndexed` and `completions: null` (omitted), the Job runs `parallelism` Pods at a time and never completes. You delete the Job when you want to stop.

This is the right pattern for "process a work queue, until I tell you to stop."

---

## 7. Patterns

### Pattern 1: One-shot task

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: backup
spec:
  backoffLimit: 0            # no retries; backup should succeed first try or alert
  ttlSecondsAfterFinished: 86400  # delete after 24h
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: backup
        image: backup:1.0
        command: ["./backup.sh"]
```

### Pattern 2: Parallel work queue (worker pool)

Process an SQS queue with 10 workers. Each Pod polls, processes, and exits. The Job creates a new Pod to keep the worker count at 10.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sqs-worker
spec:
  parallelism: 10
  completions: null           # run forever
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: worker
        image: myorg/worker:1.0
        command: ["./worker", "--queue=my-queue"]
```

This is the "Kubernetes as a worker pool" pattern. To stop, `kubectl delete job sqs-worker`. To scale, edit `parallelism`.

### Pattern 3: Indexed parallel (10 shards, 5 in parallel)

```yaml
spec:
  completionMode: Indexed
  completions: 10
  parallelism: 5
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: shard-processor
        image: myorg/processor:1.0
        env:
        - name: SHARD_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
        command: ["./process-shard", "--shard=$(SHARD_INDEX)"]
```

### Pattern 4: Sequential pipeline

Run 5 steps, one at a time, in order:

```yaml
spec:
  completions: 5
  parallelism: 1
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: step
        image: myorg/pipeline:1.0
        command: ["./step", "--index=$(JOB_COMPLETION_INDEX)"]
        env:
        - name: JOB_COMPLETION_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
```

(This requires Indexed. With NonIndexed, you can't reliably pass the step number to the script.)

### Pattern 5: Database migration (with care)

```yaml
spec:
  backoffLimit: 1            # don't retry migrations; they may be non-idempotent
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never    # see the failure
      serviceAccountName: migration-runner
      containers:
      - name: migrate
        image: myorg/app:2.1.0
        command: ["./manage", "migrate"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: url
```

**Critical:** Make sure your migrations are **idempotent** or that you have a way to detect and recover from partial migrations. Otherwise a Pod that crashes mid-migration can leave the DB in a half-migrated state.

For a real production migration, consider running the migration as an initContainer in a Deployment's first Pod, with a Job that gates the deployment:

```bash
# 1. Run the migration Job
kubectl apply -f migration-job.yaml
kubectl wait --for=condition=Complete --timeout=600s job/migration

# 2. Then deploy the new version
kubectl apply -f deployment-v2.yaml
```

### Pattern 6: Test runner (CI/CD)

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: test-runner
spec:
  backoffLimit: 0           # no retries; CI should fail fast
  activeDeadlineSeconds: 1800  # 30 min max
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: ci-runner
      containers:
      - name: test
        image: myorg/app-ci:1.0
        command: ["./run-tests"]
        resources:
          requests:
            cpu: 1
            memory: 2Gi
          limits:
            cpu: 4
            memory: 8Gi
```

For CI, the Job is typically created by the CI system (Jenkins, GitHub Actions runner) and cleaned up by `ttlSecondsAfterFinished`.

---

## 8. Suspend, Resume, and TTL

### Suspend

Pause a Job from creating new Pods:

```yaml
spec:
  suspend: true
```

The Job is "paused." Existing Pods are not affected (they keep running). New Pods are not created. You can edit the Job to change its spec while suspended, then resume.

```bash
kubectl patch job my-job -p '{"spec":{"suspend":true}}' --type=merge
```

To resume:

```bash
kubectl patch job my-job -p '{"spec":{"suspend":false}}' --type=merge
```

This is the right way to:

- Stop a runaway Job without deleting it
- Edit a Job's spec safely (e.g., bump parallelism, change image)
- Take a "snapshot" of the current state

### `ttlSecondsAfterFinished`

Auto-delete the Job (and its Pods) some time after completion:

```yaml
spec:
  ttlSecondsAfterFinished: 600
```

After 10 minutes from `Complete` or `Failed`, the Job and its Pods are deleted. Use this for:

- CI test runners (don't keep test Pods forever)
- One-shot migrations (don't keep around after success)
- Test environments

**Without `ttlSecondsAfterFinished`**, the Job and Pods stay in the cluster forever (subject to `kubectl delete`). This accumulates clutter over time.

### The TTL controller

The TTL controller is part of `kube-controller-manager`. It scans for finished Jobs and deletes them after the TTL. It runs every 30 seconds by default.

If you don't see Jobs being deleted after the TTL, check that:

- The TTL controller is enabled (it is by default)
- The Job has actually reached `Complete` or `Failed` (check `status.conditions`)

---

## 9. Active Deadline — Bounding Job Runtime

`activeDeadlineSeconds` puts a hard wall-clock limit on the Job:

```yaml
spec:
  activeDeadlineSeconds: 3600
```

If the Job hasn't reached `Complete` after 3600 seconds, the Job is marked Failed and all its Pods are terminated.

Use this for:

- "If this doesn't finish in 1 hour, something's wrong, kill it."
- Bounding costs on a runaway Job
- Compliance requirements (e.g., "no job may run longer than 4 hours")

The deadline applies to the **Job**, not the **Pod**. A single Pod with a 1-hour deadline inside a Job with a 30-minute deadline will be killed at 30 minutes by the Job's deadline.

### When the deadline fires

1. The Job's `activeDeadlineSeconds` is reached
2. The Job controller deletes all active Pods
3. The Job is marked `Failed` with `reason: DeadlineExceeded`
4. The Job is not retried — it's permanently failed

The Pods are deleted with the normal grace period (their `terminationGracePeriodSeconds`). They are not force-killed unless the grace period expires.

### Setting per-Pod deadlines

You can also set `activeDeadlineSeconds` on the Pod spec:

```yaml
spec:
  template:
    spec:
      activeDeadlineSeconds: 600   # each Pod may run at most 10 minutes
```

This bounds the time a single attempt can take. Different from the Job's `activeDeadlineSeconds`, which bounds the total wall time.

---

## 10. Job and Pod Lifecycle Integration

### The chain

```
Job created
  │
  ▼
Job controller creates Pod (sets controller-uid label, owner reference)
  │
  ▼
Pod scheduled, starts running
  │
  ├── exits 0 (success) ──▶ Pod deleted ──▶ Job counts completion
  │
  ├── exits non-zero (OnFailure) ──▶ container restarted in place ──▶ retry counted
  │
  ├── exits non-zero (Never) ──▶ Pod left for inspection ──▶ new Pod created ──▶ retry counted
  │
  └── killed externally (eviction, drain, etcd loss) ──▶ Pod gone, no failure count
```

### What the Job controller does to a Pod

When the Job controller creates a Pod, it:

1. Adds a label `controller-uid: <uid>` so the Pod is owned by this Job
2. Sets the Pod's owner reference to the Job
3. When the Job is deleted, all Pods are deleted (cascading)

If you delete a Pod manually (e.g., `kubectl delete pod`), the Job controller sees the missing Pod and creates a new one (subject to `backoffLimit`). This is **not** a "failure" — it's treated as an external eviction.

### Labels for tracking

Pods created by a Job have the label:

```
batch.kubernetes.io/controller-uid: <job-uid>
```

You can find all Pods of a Job with:

```bash
kubectl get pods -l batch.kubernetes.io/controller-uid=<job-uid>
# or, easier:
kubectl get pods -l job-name=<job-name>
```

The `job-name` label is also added automatically (since k8s 1.27+ for legacy compat).

### Why Pods aren't deleted on success

When a Pod succeeds:

1. The Pod exits 0
2. The kubelet reports the exit to the API server
3. The Pod stays in `Terminated` state (not deleted yet)
4. The Job counts the completion
5. **The Pod is left around** so you can inspect logs and status

The Pod is deleted when:

- The Job is deleted (cascading)
- `ttlSecondsAfterFinished` fires (deletes the whole Job)
- You delete the Pod manually

This is by design — keeping terminated Pods around lets you see the results of the run.

---

## 11. Operational Recipes

### Recipe 1: Wait for a Job to complete

```bash
kubectl wait --for=condition=Complete --timeout=600s job/<name>
```

Or for failure:

```bash
kubectl wait --for=condition=Failed --timeout=600s job/<name>
```

This is the right pattern for CI/CD: run a Job, wait for it to finish, then continue.

### Recipe 2: Get Job logs

```bash
# All logs from all Pods of the Job
kubectl logs -l job-name=<name> --tail=100

# A specific Pod (useful for Indexed Jobs)
kubectl logs <pod-name>

# Previous container (if restartPolicy: OnFailure)
kubectl logs <pod-name> --previous
```

### Recipe 3: Re-run a failed Job

```bash
# Delete the failed Job (with its Pods)
kubectl delete job <name>

# Re-create from the same manifest
kubectl apply -f job.yaml
```

If you want to keep history, create a new Job with a different name (e.g., append a timestamp):

```bash
kubectl create -f job.yaml --name=<name>-$(date +%s)
```

### Recipe 4: Suspend and edit

```bash
# Suspend
kubectl patch job <name> -p '{"spec":{"suspend":true}}' --type=merge

# Edit (e.g., change parallelism)
kubectl edit job <name>

# Resume
kubectl patch job <name> -p '{"spec":{"suspend":false}}' --type=merge
```

### Recipe 5: Watch Job progress

```bash
watch -n 1 'kubectl get job <name> -o jsonpath="Active={.status.active}, Succeeded={.status.succeeded}, Failed={.status.failed}"'
```

Or:

```bash
kubectl get job <name> -w
```

### Recipe 6: Clean up finished Jobs

```bash
# Find all completed Jobs older than 1 day (without TTL)
kubectl get jobs -A -o json | \
  jq -r '.items[] | select(.status.conditions[]?.type == "Complete") | "\(.metadata.namespace)/\(.metadata.name)"' | \
  while read j; do
    age=$(kubectl get job -n "${j%/*}" "${j#*/}" -o jsonpath='{.status.completionTime}' 2>/dev/null)
    if [ -n "$age" ]; then
      # Parse and compare to now
      ...
    fi
  done
```

Easier: just use `ttlSecondsAfterFinished` in the Job spec and the TTL controller handles it.

---

## 12. Troubleshooting

### Symptom: Job is stuck in `Running` with no completions

**Check 1: Are the Pods actually running?**

```bash
kubectl get pods -l job-name=<name>
```

If they're in `Pending`, see "Pending Pods" below. If they're in `CrashLoopBackOff`, see "Pod keeps crashing" below.

**Check 2: Is `parallelism` set correctly?**

If `parallelism: 1` and `completions: 10`, only one Pod runs at a time. Wait for the first to succeed, then the next starts.

**Check 3: Is the Job suspended?**

```bash
kubectl get job <name> -o jsonpath='{.spec.suspend}'
# "true" means suspended
```

If suspended, set `spec.suspend: false`.

### Symptom: Pods are Pending

```bash
kubectl describe pod <pod>
```

Common causes:

- **Insufficient resources** — Job's parallelism exceeds node capacity
- **Volume mount failure** — PVC not bound, hostPath missing
- **Taint without toleration** — the node is tainted, the Pod doesn't tolerate
- **Image pull error** — bad image tag, registry auth issue
- **Quota exceeded** — namespace quota doesn't allow the requested resources

### Symptom: Pod keeps crashing (CrashLoopBackOff)

```bash
kubectl logs <pod> --previous
```

Common causes:

- **Bad command** — the script exits with non-zero on startup
- **Missing dependencies** — the script can't find a tool or library
- **Permission errors** — the container can't write to a volume
- **Misconfiguration** — env var is wrong, secret is missing

If `restartPolicy: OnFailure`, the container restarts in place. After `backoffLimit` retries, the Job is Failed.

If `restartPolicy: Never`, the failed Pod is left around and a new Pod is created. You can `kubectl logs` the old one.

### Symptom: `Job has reached the specified backoff limit`

The Job is permanently failed. To recover:

1. Investigate the failed Pods (`kubectl logs <pod>`, `kubectl describe pod <pod>`)
2. Fix the underlying issue
3. Delete the Job and create a new one

There is no "retry from where it left off" — the Job is dead.

### Symptom: Job is Complete but Pods are still around

This is by design. Pods of a Complete Job stay around for inspection. To clean up:

- Set `ttlSecondsAfterFinished` in the Job spec (works for new Jobs)
- Delete the Job manually (cascades to Pods)
- For old Jobs, use a cleanup script

### Symptom: Job won't scale up

You change `parallelism: 5` to `parallelism: 20` and the Job doesn't scale.

Check:

- Is the Job suspended? (`spec.suspend: true`)
- Is the cluster out of resources?
- Is the namespace quota exceeded?
- Are you editing the right field? (`spec.parallelism`, not `spec.template.spec.parallelism`)

### Symptom: Index isn't being passed to the script

You're using `Indexed` completion mode but the script doesn't see `JOB_COMPLETION_INDEX`. Check:

1. The env var is set in the Pod spec (see example in section 6)
2. You're reading the env var, not a CLI arg
3. The Pod is actually `Indexed` (check `status.completionMode` or the Job's spec)

The env var is set by the kubelet when the Pod is created by a Job controller in `Indexed` mode. If you create the Pod manually (don't do this), the env var is not set.

### Symptom: "Job is dead but Pods are stuck in Terminating"

Pods of a Job that was deleted can get stuck in Terminating if they have finalizers or long graceful shutdown.

Check:

- Is there a `preStop` hook that hangs?
- Is the kubelet healthy?
- Is the volume mount blocking?

Force-delete:

```bash
kubectl delete pod <pod> --force --grace-period=0
```

---

## 13. Gotchas and Common Mistakes

### Restart policy gotchas

- **`restartPolicy: Always` is rejected.** Use `OnFailure` or `Never`.
- **Default `restartPolicy` for Pods is `Always`** — but for Jobs, the API server overrides this. If you copy a Pod spec from a Deployment and put it in a Job, double-check the `restartPolicy`.
- **With `OnFailure`, all retries are in the same Pod.** Logs accumulate. Use `--previous` to see earlier attempts.

### Backoff gotchas

- **Default `backoffLimit` is 4 in modern clusters, 6 in older ones.** Always set it explicitly.
- **Exponential backoff can be slow.** A `backoffLimit: 4` Job can take ~2.5 minutes of backoff before failing.
- **Evictions don't count toward `backoffLimit`.** A Pod that gets evicted is replaced without a failure being counted.
- **`backoffLimit` is per-Job, not per-Pod.** If you have a parallel Job, one Pod's failure doesn't fail the whole Job unless it hits the limit.

### Completion mode gotchas

- **Default `completionMode` is `NonIndexed`.** If you want indices, you must specify.
- **Indexed Jobs need explicit env-var setup** to pass the index to the container.
- **`completions: null` with `NonIndexed` runs forever.** The Job is never Complete. You must delete it.

### TTL gotchas

- **The TTL controller is part of `kube-controller-manager`.** If the controller-manager is down, Jobs aren't garbage-collected.
- **`ttlSecondsAfterFinished` is measured from `completionTime` or `failureTime`.** Not from when you set the field.
- **TTL is per-Job, not per-Pod.** When the Job is deleted, the Pods are deleted via owner references.

### Active deadline gotchas

- **The deadline is wall-clock, not CPU time.** A Pod that's been preempted or evicted still counts.
- **The deadline applies to the Job.** Per-Pod deadlines are set separately.
- **When the deadline fires, the Job is Failed.** The Pods are deleted. There is no retry.

### Resource gotchas

- **Job Pods count against your namespace quota.** A Job with `parallelism: 1000` on a small quota won't schedule.
- **Job Pods are scheduled as normal Pods.** They don't get special placement; they go through the scheduler.
- **Job resources should be set in the Pod template.** They are not part of the Job spec.

### Other gotchas

- **A Job is not restarted when its node dies.** The Pod is rescheduled on a new node (no failure counted).
- **A Job is not "auto-scaled."** HPA doesn't work on Jobs. For dynamic batch processing, use a custom controller or KEDA.
- **Job history is per-namespace, not global.** If you have thousands of Jobs over time, clean up with `ttlSecondsAfterFinished`.
- **`Job`'s `selector` is auto-generated.** Don't try to set it manually unless you know what you're doing.
- **A failed Job's Pods may still hold locks or other resources.** The script is responsible for cleanup on failure. The kubelet doesn't know about your database transactions.

---

## 14. Related Notes

| Topic | Note |
|---|---|
| Pods (what a Job runs) | [[Kubernetes/concepts/L03-workloads/01-pods\|01 — Pods]] |
| CronJob (scheduled Jobs) | [[Kubernetes/concepts/L03-workloads/07-cronjob\|07 — CronJob]] |
| Deployment (long-running) | [[Kubernetes/concepts/L03-workloads/03-deployments\|03 — Deployments]] |
| Init containers (run before app) | [[Kubernetes/concepts/L03-workloads/08-init-containers\|08 — Init Containers]] |
| Resource requests and limits | [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|L06 — Resource Requests and Limits]] |
| Taints and tolerations | [[Kubernetes/concepts/L06-scheduling-scaling\|L06 — Scheduling and Scaling]] |
| TTL controller (advanced) | [[Kubernetes/concepts/L09-advanced/06-garbage-collection\|L09 — Garbage Collection]] |
| Finalizers (advanced) | [[Kubernetes/concepts/L09-advanced/05-finalizers\|L09 — Finalizers]] |
