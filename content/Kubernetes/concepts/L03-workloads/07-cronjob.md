# CronJob

*"https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/"*

A CronJob runs [[Kubernetes/concepts/L03-workloads/06-job|Jobs]] on a **time-based schedule**. Think of it as the k8s equivalent of `crontab(5)`.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
spec:
  schedule: "0 2 * * *"            # 02:00 every day
  timeZone: "Etc/UTC"               # k8s 1.25+
  startingDeadlineSeconds: 200      # miss window, don't run
  concurrencyPolicy: Forbid         # see below
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: backup:1.0
          restartPolicy: OnFailure
```

## Schedule syntax

Standard cron with the addition of `@hourly`, `@daily`, `@weekly`, `@monthly`, `@yearly`.

`spec.timeZone` (k8s 1.25+) lets you specify a timezone (e.g. `"America/New_York"`) instead of inheriting the controller's TZ.

## Concurrency policies

What happens if a Job is still running when the next scheduled time arrives:

* `Allow` (default) — overlapping Jobs are allowed (parallel cron runs)
* `Forbid` — skip the new run if the previous one is still active
* `Replace` — kill the previous Job's Pods and start the new one

`Forbid` is the safe default for backups. `Replace` is for cases where you always want the latest run (e.g. cache warmer — though you should probably not use CronJob for that).

## Suspend

`spec.suspend: true` pauses scheduling. Useful for disabling a CronJob temporarily without deleting it.

## Gotchas

* **Schedules are evaluated by the controller-manager**, not by the kubelet. If the controller-manager is down, no CronJobs fire. There is no leader election redundancy for the scheduler logic itself.
* **CronJob does not compensate for missed runs** (unlike some external schedulers). If the controller is offline for 3 hours, the 3 missed runs are lost — unless you set `startingDeadlineSeconds` high enough that the controller still considers them valid when it comes back.
* **A CronJob creates a Job, not Pods directly.** `kubectl get jobs` will show the historical jobs. `kubectl get pods -l job-name=...` shows the Pods of a specific Job.
* **Don't put long-running workloads in a CronJob.** Use a Deployment. CronJob is for run-to-completion tasks.
* **The Job's history limits matter** — they're set per CronJob. If you create 100 CronJobs with default limits, you'll keep 300 historical Jobs in etcd.
* **CronJob does not react to time changes** (NTP slew, DST). The k8s docs are explicit about this.

## CronJob vs external schedulers

For simple "run X every Y" you don't need Airflow / Argo Workflows. Reach for them when you have:

* DAG dependencies (run B after A succeeds)
* Backfills / retries across many days
* SLA-based scheduling
