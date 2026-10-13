---
title: "Lab CKAD-10 — Jobs, CronJobs & Multi-Container Pods"
tags: [kubernetes, labs, ckad, jobs, cronjobs, init-containers, sidecar]
date: 2026-10-13
description: Run work to completion with Jobs and CronJobs, read why a Job failed, and build a Pod with an init container, a sidecar and shared volumes.
---

# Lab CKAD-10 — Jobs, CronJobs & Multi-Container Pods

A Deployment is the right controller only for a process that should run for ever. This lab covers the other cases the CKAD objectives name: work that runs **to completion** (Job), work that runs **on a schedule** (CronJob), and Pods where **several containers cooperate** (init containers and sidecars).

Concepts: [[Kubernetes/concepts/L03-workloads/06-job|Jobs]], [[Kubernetes/concepts/L03-workloads/07-cronjob|CronJobs]], [[Kubernetes/concepts/L03-workloads/08-init-containers|Init Containers]] and [[Kubernetes/concepts/L03-workloads/09-multi-container-pods|Multi-Container Pods]].

Tested 2026-10-13 on kind v0.33.0 with Kubernetes v1.37.0.

| Requirement                                   | Controller  |
| :-------------------------------------------- | :---------- |
| Keep N copies running, replace them on change | Deployment  |
| Stable name and its own volume per replica    | StatefulSet |
| One copy on every node                        | DaemonSet   |
| Run until it succeeds, then stop              | Job         |
| Run a Job at set times                        | CronJob     |

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**. No other lab is required.

```bash
kubectl create namespace batch-lab
kubectl config set-context --current --namespace=batch-lab
```

---

## 2. Jobs

### Step 1: A Job that runs once

```bash
kubectl create job pi --image=busybox:1.36 -- sh -c 'echo "result: 3.14159"; sleep 2'
kubectl wait --for=condition=complete job/pi --timeout=60s

kubectl get job pi
kubectl get pods -l job-name=pi
kubectl logs job/pi
```

```
NAME   STATUS     COMPLETIONS   DURATION   AGE
pi     Complete   1/1           6s         6s

NAME       READY   STATUS      RESTARTS   AGE
pi-rj8q2   0/1     Completed   0          6s

result: 3.14159
```

The Pod is `Completed`, not `Running`, and it is kept so that you can read its logs. A Job's Pod template must use `restartPolicy: Never` or `OnFailure`; `Always` is rejected, because a Job has to be able to finish.

### Step 2: Several completions, some in parallel

`kubectl create job` has no flags for the fields that matter most. Generate the manifest and edit it:

```bash
kubectl create job batch --image=busybox:1.36 --dry-run=client -o yaml \
  -- sh -c 'echo "item done on $(hostname)"; sleep 3' > batch.yaml
```

Add four lines under `spec:` so that the file reads:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: batch
spec:
  completions: 6
  parallelism: 2
  backoffLimit: 2
  ttlSecondsAfterFinished: 300
  template:
    spec:
      containers:
        - command:
            - sh
            - -c
            - echo "item done on $(hostname)"; sleep 3
          image: busybox:1.36
          name: batch
      restartPolicy: Never
```

```bash
kubectl apply -f batch.yaml
kubectl get pods -l job-name=batch
kubectl wait --for=condition=complete job/batch --timeout=120s
kubectl get job batch
```

```
NAME    STATUS     COMPLETIONS   DURATION   AGE
batch   Complete   6/6           18s        18s
```

| Field                     | Meaning                                                              |
| :------------------------ | :------------------------------------------------------------------- |
| `completions`             | How many Pods must succeed in total                                  |
| `parallelism`             | How many may run at the same time                                    |
| `backoffLimit`            | How many failed Pods are tolerated before the Job is marked `Failed` |
| `activeDeadlineSeconds`   | A time limit for the whole Job, whatever the number of retries       |
| `ttlSecondsAfterFinished` | Delete the Job and its Pods this long after it finishes              |

Six completions at two at a time, three seconds each, took about 18 seconds, as the arithmetic says.

### Step 3: Controlled failure: a Job that cannot succeed

```bash
kubectl create job flaky --image=busybox:1.36 --dry-run=client -o yaml \
  -- sh -c 'echo "cannot reach upstream"; exit 1' \
  | sed 's/^spec:/spec:\n  backoffLimit: 2\n  activeDeadlineSeconds: 120/' \
  | kubectl apply -f -

kubectl wait --for=condition=failed job/flaky --timeout=120s
kubectl get job flaky
kubectl get pods -l job-name=flaky
kubectl get job flaky -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
kubectl logs job/flaky
```

```
NAME    STATUS   COMPLETIONS   DURATION   AGE
flaky   Failed   0/1           50s        50s

NAME          READY   STATUS   RESTARTS   AGE
flaky-4gcg7   0/1     Error    0          50s
flaky-dpgcp   0/1     Error    0          40s
flaky-f7jd4   0/1     Error    0          20s

FailureTarget=True BackoffLimitExceeded: Job has reached the specified backoff limit
Failed=True BackoffLimitExceeded: Job has reached the specified backoff limit

cannot reach upstream
```

`backoffLimit: 2` allowed three attempts in total: the first and two retries, with a growing delay between them. The Job's **condition** says why it stopped (`BackoffLimitExceeded`), and a Pod's **log** says why the work failed. You need both. With `restartPolicy: Never` each attempt is a new Pod, which keeps every attempt's log; with `OnFailure` the same Pod restarts its container and only the latest log is easy to reach.

A Job's template cannot be edited once it is created. To fix one, delete it and create it again.

---

## 3. CronJobs

```bash
kubectl create cronjob report --image=busybox:1.36 --schedule='*/1 * * * *' \
  -- sh -c 'date; echo report written'
kubectl get cronjob report
```

```
NAME     SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
report   */1 * * * *   <none>     False     0        <none>          0s
```

The schedule is standard cron: minute, hour, day of month, month, day of week. `TIMEZONE <none>` means the controller manager's time zone, which is usually UTC; set `spec.timeZone` to be explicit.

Do not wait for the clock to test it. Run it now:

```bash
kubectl create job report-now --from=cronjob/report
kubectl wait --for=condition=complete job/report-now --timeout=60s
kubectl logs job/report-now
```

```
Tue Oct 13 11:08:46 UTC 2026
report written
```

Set the fields a task is likely to ask for:

```bash
kubectl patch cronjob report -p '{"spec":{
  "suspend": true,
  "concurrencyPolicy": "Forbid",
  "successfulJobsHistoryLimit": 2,
  "failedJobsHistoryLimit": 1,
  "startingDeadlineSeconds": 30}}'
kubectl get cronjob report
```

| Field                                                   | Meaning                                                                                 |
| :------------------------------------------------------ | :-------------------------------------------------------------------------------------- |
| `concurrencyPolicy`                                     | `Allow` (default), `Forbid` (skip a run while the last one is still going) or `Replace` |
| `startingDeadlineSeconds`                               | How late a run may start before it counts as missed                                     |
| `successfulJobsHistoryLimit` / `failedJobsHistoryLimit` | How many finished Jobs to keep                                                          |
| `suspend`                                               | Stop creating new Jobs; running ones continue                                           |

The Job settings from section 2 live one level down in a CronJob, under `spec.jobTemplate.spec`. Use `kubectl explain cronjob.spec.jobTemplate.spec` to find the path.

---

## 4. Multi-Container Pods

Containers in one Pod share a network namespace (they reach each other on `localhost`) and can share volumes. Two patterns use that:

- an **init container** runs to completion before the application starts;
- a **sidecar** runs beside the application for the Pod's whole life. In current Kubernetes a sidecar is written as an init container with `restartPolicy: Always`, which starts it before the application and stops it after.

```bash
cat << 'EOF' > web-with-helpers.yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels:
    app: web
spec:
  initContainers:
    - name: fetch-content
      image: busybox:1.36
      command: ["sh", "-c", "echo '<h1>prepared by the init container</h1>' > /work/index.html"]
      volumeMounts:
        - name: html
          mountPath: /work
    - name: log-shipper
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh", "-c", "touch /logs/access.log; tail -n +1 -F /logs/access.log"]
      volumeMounts:
        - name: logs
          mountPath: /logs
  containers:
    - name: web
      image: busybox:1.36
      command: ["sh", "-c", "httpd -f -p 8080 -h /www -v 2>> /logs/access.log"]
      ports:
        - containerPort: 8080
      volumeMounts:
        - name: html
          mountPath: /www
          readOnly: true
        - name: logs
          mountPath: /logs
  volumes:
    - name: html
      emptyDir: {}
    - name: logs
      emptyDir: {}
EOF

kubectl apply -f web-with-helpers.yaml
kubectl wait --for=condition=Ready pod/web --timeout=90s
kubectl get pod web
```

```
NAME   READY   STATUS    RESTARTS   AGE
web    2/2     Running   0          1s
```

`READY 2/2` counts the application and the sidecar. The ordinary init container has finished and is not counted.

Send two requests and read each container's output:

```bash
kubectl exec web -c web -- wget -qO- localhost:8080
kubectl exec web -c web -- wget -qO- localhost:8080/missing

kubectl logs web -c log-shipper
kubectl logs web --all-containers --prefix
```

```
<h1>prepared by the init container</h1>
wget: server returned error: HTTP/1.1 404 Not Found

[::ffff:127.0.0.1]:48276: response:200
[::ffff:127.0.0.1]:48300: response:404

[pod/web/log-shipper] [::ffff:127.0.0.1]:48276: response:200
[pod/web/log-shipper] [::ffff:127.0.0.1]:48300: response:404
```

- The page was written by `fetch-content` into an `emptyDir`, and the web server reads it from the same volume, mounted read-only at a different path.
- The web server writes its access log to a file. The sidecar reads that file from the shared `logs` volume and prints it, which makes it available to `kubectl logs`.
- With more than one container, name the one you mean with `-c`. Without it, `kubectl` picks a default and tells you so.

### Controlled failure: an init container that never finishes

```bash
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: stuck
spec:
  initContainers:
    - name: wait-for-db
      image: busybox:1.36
      command: ["sh", "-c", "until nslookup db.batch-lab.svc.cluster.local; do echo waiting for db; sleep 2; done"]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
EOF

sleep 12
kubectl get pod stuck
kubectl logs stuck
kubectl logs stuck -c wait-for-db | tail -n 1
```

```
NAME    READY   STATUS     RESTARTS   AGE
stuck   0/1     Init:0/1   0          12s

Defaulted container "app" out of: app, wait-for-db (init)
Error from server (BadRequest): container "app" in pod "stuck" is waiting to start: PodInitializing

waiting for db
```

`Init:0/1` means zero of one init containers have completed. The application container has not started, so it has no logs; the evidence is in the **init container's** log. Other statuses in the same family are `Init:Error` and `Init:CrashLoopBackOff`.

The init container is waiting for a Service name to resolve. Create the Service:

```bash
kubectl create service clusterip db --tcp=5432:5432
kubectl wait --for=condition=Ready pod/stuck --timeout=60s
kubectl get pod stuck
```

```
NAME    READY   STATUS    RESTARTS   AGE
stuck   1/1     Running   0          13s
```

---

## 5. Cleanup

```bash
kubectl config set-context --current --namespace=default
kubectl delete namespace batch-lab
rm -f batch.yaml web-with-helpers.yaml
```

---

## Practice Without the Answer

Suggested time: 12 minutes for all three. Work in a new namespace `jobs`.

1. Create a Job `backup` (image `busybox:1.36`) that prints `backup complete`, must succeed 4 times, runs 2 at a time, and is deleted 60 seconds after it finishes.
2. Create a CronJob `cleanup` that runs every 15 minutes, never overlaps with itself, keeps 1 successful Job, and gives each run at most 30 seconds before it is killed. Trigger one run by hand.
3. Create a Pod `shared` with two containers: `writer` (appends the date to `/data/out.txt` every 5 seconds) and `reader` (runs `tail -f /data/out.txt`). The file must not survive the Pod.

Check yourself:

```bash
kubectl -n jobs get job backup -o jsonpath='{.spec.completions} {.spec.parallelism} {.spec.ttlSecondsAfterFinished}{"\n"}'   # 4 2 60
kubectl -n jobs get cronjob cleanup -o jsonpath='{.spec.schedule} {.spec.concurrencyPolicy} {.spec.successfulJobsHistoryLimit} {.spec.jobTemplate.spec.activeDeadlineSeconds}{"\n"}'   # */15 * * * * Forbid 1 30
kubectl -n jobs get jobs                              # backup, and one created from cleanup
kubectl -n jobs logs shared -c reader --tail=2        # two dates
kubectl -n jobs get pod shared -o jsonpath='{.spec.volumes[0].emptyDir}{"\n"}'   # {}
```

Reset with `kubectl delete namespace jobs`.

---

## Further reading

- [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Init containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Sidecar containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)

## Next Lab

Proceed to **[[Kubernetes/labs/ckad/11-helm-release-lifecycle|Lab CKAD-11 — Helm Release Lifecycle]]**, or return to the [[Kubernetes/certifications/ckad|CKAD Track]].
