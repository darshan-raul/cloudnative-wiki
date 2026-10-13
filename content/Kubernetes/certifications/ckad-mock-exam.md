---
title: CKAD Practice Set
tags: [kubernetes, certifications, ckad, exam-prep, practice]
date: 2026-10-13
description: "A timed, mixed set of ten original CKAD-style tasks with a setup script, the state each task must reach, and a check for each one."
---

# CKAD Practice Set

Ten tasks across the five CKAD domains, to be done in one sitting. These are original practice tasks written for this wiki. They are **not** reconstructions of exam questions, and a score here is not a prediction of an exam result. What the set does measure is whether you can move between unrelated tasks, in the right namespace, and verify your own work against a clock.

The setup script, a reference solution and every check below were run on kind v0.33.0 with Kubernetes v1.37.0 on 2026-10-13.

Part of the [[Kubernetes/certifications/ckad|CKAD Track]].

---

## Rules

- **Time:** 90 minutes for the ten tasks. The real exam gives two hours for 15 to 20 tasks, so the pace is similar.
- **Documentation:** only `kubernetes.io/docs`, `kubernetes.io/blog` and `helm.sh/docs`, as in the exam.
- **Do not open the labs** while the clock runs.
- **Each task has its own namespace.** An object in the wrong namespace earns nothing, exactly as in the exam.
- Do the tasks in any order. Flag one that stalls and return to it.
- Run the checks **after** time is up, not while working. During the set, verify in whatever way you would in the exam.

## Setup

Use the lab cluster from [[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]. Run this once, and do not study it:

```bash
cat << 'SETUP' > ckad-setup.sh
for N in m1 m2 m3 m4 m5 m6 m7 m8 m9 m10; do kubectl create namespace $N; done
kubectl -n m2 create deployment store --image=ghcr.io/stefanprodan/podinfo:6.7.0 --replicas=3
kubectl -n m3 create deployment api --image=ghcr.io/stefanprodan/podinfo:6.7.1 --port=9898
kubectl -n m3 create service clusterip api --tcp=80:8080
kubectl -n m3 patch service api -p '{"spec":{"selector":{"app":"api-server"}}}'
kubectl -n m3 run client --image=curlimages/curl:8.10.1 --command -- sleep 7200
kubectl -n m5 create quota budget --hard=pods=3,requests.cpu=300m,requests.memory=300Mi
kubectl -n m6 create deployment worker --image=busybox:1.36 -- sh -c 'test -f /etc/app/mode || { echo "missing /etc/app/mode" >&2; exit 4; }; echo "mode=$(cat /etc/app/mode)"; sleep 3600'
kubectl -n m8 create deployment db --image=ghcr.io/stefanprodan/podinfo:6.7.1 --port=9898
kubectl -n m8 expose deployment db --port=9898
kubectl -n m8 run web --image=curlimages/curl:8.10.1 --labels=tier=web --command -- sleep 7200
kubectl -n m8 run other --image=curlimages/curl:8.10.1 --command -- sleep 7200
kubectl -n m9 create deployment legacy --image=ghcr.io/stefanprodan/podinfo:6.7.1
kubectl -n m10 create deployment v1 --image=ghcr.io/stefanprodan/podinfo:6.7.0 --replicas=4
kubectl -n m10 patch deployment v1 --type json -p '[{"op":"add","path":"/spec/template/metadata/labels/shop","value":"true"}]'
kubectl -n m10 create service clusterip shop --tcp=80:9898
kubectl -n m10 patch service shop -p '{"spec":{"selector":{"app":null,"shop":"true"}}}'
SETUP
sh ckad-setup.sh > /dev/null 2>&1
```

Start the clock.

---

## Tasks

| #   | Namespace | Weight | Domain                               |
| :-- | :-------- | :----- | :----------------------------------- |
| 1   | `m1`      | 10     | Design and Build                     |
| 2   | `m2`      | 10     | Deployment                           |
| 3   | `m3`      | 10     | Services and Networking              |
| 4   | `m4`      | 10     | Environment, Configuration, Security |
| 5   | `m5`      | 10     | Environment, Configuration, Security |
| 6   | `m6`      | 12     | Observability and Maintenance        |
| 7   | `m7`      | 10     | Environment, Configuration, Security |
| 8   | `m8`      | 10     | Services and Networking              |
| 9   | `m9`      | 8      | Observability and Maintenance        |
| 10  | `m10`     | 10     | Deployment                           |

**Task 1 (`m1`).** Create a Job `report` using image `busybox:1.36` that prints `done`. It must succeed 3 times, run all 3 at once, and tolerate at most 1 failed Pod. Also create a CronJob `nightly` with the same image that runs `date` at 02:30 every day, never runs two instances at once, and keeps 2 successful Jobs.

**Task 2 (`m2`).** Deployment `store` runs `ghcr.io/stefanprodan/podinfo:6.7.0`. Configure it so that a rolling update never has fewer than 3 ready Pods and adds at most 1 extra. Update it to image tag `6.7.1`. Then roll back to the previous revision, and write the output of the Deployment's rollout history to `/tmp/m2-history.txt`.

**Task 3 (`m3`).** Pod `client` cannot reach `http://api/`. Service `api` should send traffic to the Pods of Deployment `api`. Fix the Service. Do not change the Deployment.

**Task 4 (`m4`).** Create a ConfigMap `app-config` with `LOG_LEVEL=debug` and `REGION=eu`, and a Secret `app-secret` with `API_KEY=abc123`. Create a Pod `app` (image `busybox:1.36`, command `sleep 3600`) that has every key of the ConfigMap as an environment variable and the Secret mounted read-only at `/etc/secret`.

**Task 5 (`m5`).** The namespace has a ResourceQuota. Create a Deployment `cache` with 2 replicas of `busybox:1.36` running `sleep 3600`, each requesting `100m` CPU and `64Mi` memory, with memory limited to `64Mi`. Both replicas must be running.

**Task 6 (`m6`).** Deployment `worker` is not becoming ready. Find out why from the cluster, and fix it without changing the container's image or command. The application expects the value `production`.

**Task 7 (`m7`).** Create a Pod `secure` (image `busybox:1.36`, command `sleep 3600`) that runs as user ID 2000, cannot run as root, cannot gain privileges, has a read-only root filesystem, has no Linux capabilities, and has no ServiceAccount token mounted.

**Task 8 (`m8`).** Allow connections to the Pods of Deployment `db` on TCP 9898 only from Pods labelled `tier=web` in the same namespace. Pod `web` must still reach `http://db:9898/`; Pod `other` must not. Do not change any Pod's labels.

**Task 9 (`m9`).** Add to Deployment `legacy` a readiness probe on `GET /readyz` port 9898 checked every 5 seconds, and a liveness probe on `GET /healthz` port 9898 that starts after 10 seconds and restarts the container after 3 consecutive failures.

**Task 10 (`m10`).** Service `shop` sends traffic to the 4 Pods of Deployment `v1`. Introduce a Deployment `v2` running `ghcr.io/stefanprodan/podinfo:6.7.1` so that about a quarter of the Service's traffic reaches it, keeping the total number of Pods behind the Service at 4.

---

## Checks

Stop the clock first. Each block prints what a correct result looks like in the comment. Award the task's full weight only if every line matches; a partial result earns nothing, as in the exam.

```bash
# 1 (10): 3 3 3   and   30 2 * * * Forbid 2
kubectl -n m1 get job report -o jsonpath='{.spec.completions} {.spec.parallelism} {.status.succeeded}{"\n"}'
kubectl -n m1 get job report -o jsonpath='{.spec.backoffLimit}{"\n"}'     # 1
kubectl -n m1 get cronjob nightly -o jsonpath='{.spec.schedule} {.spec.concurrencyPolicy} {.spec.successfulJobsHistoryLimit}{"\n"}'

# 2 (10): ...podinfo:6.7.0 0 1 3   and a non-empty file with at least two revisions
kubectl -n m2 get deployment store -o jsonpath='{.spec.template.spec.containers[0].image} {.spec.strategy.rollingUpdate.maxUnavailable} {.spec.strategy.rollingUpdate.maxSurge} {.status.readyReplicas}{"\n"}'
cat /tmp/m2-history.txt

# 3 (10): 200
kubectl -n m3 exec client -- curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://api/

# 4 (10): debug eu   then   abc123
kubectl -n m4 exec app -- sh -c 'echo $LOG_LEVEL $REGION; cat /etc/secret/API_KEY; echo'
kubectl -n m4 get pod app -o jsonpath='{.spec.containers[0].volumeMounts[?(@.mountPath=="/etc/secret")].readOnly}{"\n"}'   # true

# 5 (10): 2   then   {"limits":{"memory":"64Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}
kubectl -n m5 get deployment cache -o jsonpath='{.status.readyReplicas}{"\n"}'
kubectl -n m5 get pods -o jsonpath='{.items[0].spec.containers[0].resources}{"\n"}'

# 6 (12): mode=production   then   1
kubectl -n m6 logs deployment/worker
kubectl -n m6 get deployment worker -o jsonpath='{.status.readyReplicas}{"\n"}'

# 7 (10): 2000, CapBnd all zeros, NoNewPrivs 1, "Read-only file system", "No such file or directory"
kubectl -n m7 exec secure -- sh -c 'id -u; grep -E "NoNewPrivs|CapBnd" /proc/1/status; touch /x; ls /var/run/secrets/kubernetes.io'
kubectl -n m7 get pod secure -o jsonpath='{.spec.containers[0].securityContext.runAsNonRoot}{.spec.securityContext.runAsNonRoot}{"\n"}'   # true

# 8 (10): web 200   then   other 000 (and a timeout)
kubectl -n m8 exec web -- curl -s -m 4 -o /dev/null -w 'web %{http_code}\n' http://db:9898/
kubectl -n m8 exec other -- curl -s -m 4 -o /dev/null -w 'other %{http_code}\n' http://db:9898/

# 9 (8): /readyz 5 /healthz 10 3 1
kubectl -n m9 get deployment legacy -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path} {.spec.template.spec.containers[0].readinessProbe.periodSeconds} {.spec.template.spec.containers[0].livenessProbe.httpGet.path} {.spec.template.spec.containers[0].livenessProbe.initialDelaySeconds} {.spec.template.spec.containers[0].livenessProbe.failureThreshold} {.status.readyReplicas}{"\n"}'

# 10 (10): 3 v1 and 1 v2
kubectl -n m10 get endpointslices -l kubernetes.io/service-name=shop \
  -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}' | cut -d- -f1 | sort | uniq -c
kubectl -n m10 get deployment v2 -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'   # ...podinfo:6.7.1
```

The CKAD pass mark is 66%. Record your score, the time you used and which tasks you flagged.

---

## Review

For each task you missed, decide which of these it was, because the remedy differs:

| What happened                                  | What to do                                              |
| :--------------------------------------------- | :------------------------------------------------------ |
| Did not know the mechanism                     | Go back to the lab in the table below                   |
| Knew it, but could not find the syntax in time | Practise finding that page in the allowed documentation |
| Right object, wrong namespace or name          | Slow down at the start of each task; read it twice      |
| Thought it was done; the check disagreed       | Build the habit of verifying before moving on           |
| Ran out of time                                | Repeat the set in a week; note which tasks took longest |

| Task | Lab                                                                                                                                |
| :--- | :--------------------------------------------------------------------------------------------------------------------------------- |
| 1    | [[Kubernetes/labs/ckad/10-jobs-cronjobs-and-multi-container-pods\|Lab CKAD-10]]                                                    |
| 2    | [[Kubernetes/labs/ckad/03-updates-and-rollbacks\|Lab CKAD-03]]                                                                     |
| 3    | [[Kubernetes/labs/ckad/05-services-and-dns\|Lab CKAD-05]], [[Kubernetes/labs/cka/11-service-and-dns-troubleshooting\|Lab CKA-11]]  |
| 4    | [[Kubernetes/labs/ckad/04-configuration\|Lab CKAD-04]]                                                                             |
| 5    | [[Kubernetes/labs/ckad/13-quotas-limit-ranges-and-probes\|Lab CKAD-13]]                                                            |
| 6    | [[Kubernetes/labs/ckad/06-observability-and-troubleshooting\|Lab CKAD-06]], [[Kubernetes/labs/ckad/04-configuration\|Lab CKAD-04]] |
| 7    | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]]                                                                 |
| 8    | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]] section 7                                                       |
| 9    | [[Kubernetes/labs/ckad/13-quotas-limit-ranges-and-probes\|Lab CKAD-13]]                                                            |
| 10   | [[Kubernetes/labs/ckad/12-blue-green-and-canary\|Lab CKAD-12]]                                                                     |

A set you have already seen measures memory as much as skill. Before repeating it, change the names, images and numbers in the tasks, or have someone else do so.

## Reset

```bash
kubectl delete namespace m1 m2 m3 m4 m5 m6 m7 m8 m9 m10
rm -f ckad-setup.sh /tmp/m2-history.txt
```
