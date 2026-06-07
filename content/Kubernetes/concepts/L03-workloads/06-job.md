# Job

*"https://kubernetes.io/docs/concepts/workloads/controllers/job/"*

A Job runs **one or more Pods to completion** — a workload that you want to finish, not run forever. The controller ensures a specified number of Pods terminate successfully.

## When you'd use one

* Batch processing: video transcoding, image resizing, report generation
* One-shot data migrations
* Database schema migrations (with care — see gotchas)
* Anything you'd otherwise run from `cron` on a single machine

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
spec:
  completions: 5       # total successful Pods
  parallelism: 2        # run at most 2 at once
  backoffLimit: 4       # retries before marking failed
  template:
    spec:
      restartPolicy: OnFailure   # required for Jobs
      containers:
      - name: pi
        image: perl:5.34
        command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
```

## Restart policies

For a Job, `restartPolicy` can only be:

* `OnFailure` (most common) — failed container is restarted in-place
* `Never` — failed Pod is left for you to inspect; a new Pod is created

`Always` is **not allowed** for Jobs (a Job is supposed to terminate).

## Patterns

### Work queue with fixed completion count

```yaml
spec:
  completions: 100
  parallelism: 10
```

Each Pod is given an index (`JOB_COMPLETION_INDEX` env) and processes a slice of work.

### Parallelism without fixed count

```yaml
spec:
  parallelism: 10
  completions: null    # run 10 in parallel until you delete the Job
```

### Indexed Jobs (k8s 1.21+)

```yaml
spec:
  completionMode: Indexed
  completions: 10
  parallelism: 3
```

Each Pod gets a unique index 0..9. Use when you need deterministic per-Pod work assignment.

## Gotchas

* **A Job that never completes is a leaking resource.** Always set `activeDeadlineSeconds` to bound runtime.
* **`backoffLimit` resets the Pod, not the workload.** A flaky script with 100 retries will just keep failing.
* **Jobs that create K8s resources (like a CRD instance) need finalizers in that resource**, or the resource disappears when the Pod exits and the controller sees the Pod as "done".
* **By default a Job is not cleaned up.** Set `ttlSecondsAfterFinished: 600` to auto-delete after 10 minutes — important in CI/test flows.
* **Job Pods count against your quota.** A Job with `parallelism: 1000` on a small namespace quota will not schedule.
