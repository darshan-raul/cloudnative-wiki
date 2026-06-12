---
title: Chaos Engineering
tags:
  - Kubernetes
  - Non-Functional
  - Chaos-Engineering
  - Resilience
---

Chaos engineering is the practice of **deliberately breaking things** to learn how the system fails. The goal: find weaknesses before they cause outages, build confidence in your HA, and train the team to respond.

## The principles

From the [Principles of Chaos](https://principlesofchaos.org/):

1. **Build a hypothesis** around steady-state behavior
2. **Vary real-world events** (kill pods, drop network, etc.)
3. **Run experiments in production** (or staging that mirrors production)
4. **Automate experiments** to run continuously
5. **Minimize blast radius** (start small, expand)

**Steady state** is the key concept: what does "normal" look like? If you can't define it, you can't measure when chaos breaks it.

```
Hypothesis:  "If 1 of 5 web pods is killed, the system stays healthy"
Steady state: 4+ pods running, error rate <0.1%, latency <500ms p99
Experiment:    kill 1 pod, observe
Result:        matches steady state?  →  no action needed
              breaks steady state?    →  fix something, then re-test
```

## The chaos maturity model

| Level | Practice |
|-------|----------|
| 0 — Manual | Ad-hoc, no automation |
| 1 — Scripted | Bash scripts, run on demand |
| 2 — Scheduled | Cron, runs at fixed times |
| 3 — Tooled | Chaos Mesh, Litmus, Gremlin, etc. |
| 4 — Continuous | Always running, in production |
| 5 — Game days | Quarterly team exercises |

Most teams are at 1-3. **Continuous chaos in production** is a Netflix-grade practice. Start with game days and tooled experiments.

## The experiments

Common k8s chaos experiments, ordered by impact:

### Tier 1: Pod-level (start here)

**Kill a pod**

```bash
kubectl delete pod web-1
# or
kubectl exec web-1 -- kill 1
```

**What it tests:** Pod restarts, Service endpoint updates, readiness probes, PDBs.

**Steady state:** Other pods handle the load. No error rate spike.

**Hypothesis:** "If 1 of 5 web pods is killed, the Service still has 4 backends within 10s, error rate <0.1%."

**Crash a pod (OOM)**

```bash
# stress memory
kubectl exec web-1 -- sh -c "tail /dev/zero | head -c 1G > /tmp/big"
# or
kubectl exec web-1 -- stress --vm 1 --vm-bytes 1G --timeout 60
```

**What it tests:** OOMKill, pod restart, memory limit enforcement.

**Steady state:** Pod restarts, comes back. Other pods unaffected.

**Hypothesis:** "If a pod OOMs, it's restarted, memory limit is enforced, and steady-state latency is preserved."

**Throttle CPU**

```bash
# use chaos-mesh or stress
kubectl exec web-1 -- stress --cpu 4 --timeout 60
```

**What it tests:** CPU limits, throttling behavior, scheduler responses.

### Tier 2: Network-level

**Drop traffic to a Service**

```bash
# using chaos-mesh
kubectl apply -f - <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: drop-traffic
spec:
  action: partition
  selector:
    namespaces:
      - my-app
    labelSelectors:
      app: web
  direction: to
  duration: 5m
EOF
```

**What it tests:** NetworkPolicy, mTLS, retry logic, circuit breakers.

**Steady state:** App degrades gracefully, errors have a clear cause, no silent failure.

**Add latency**

```bash
# chaos-mesh
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: add-latency
spec:
  action: delay
  delay:
    latency: 500ms
    correlation: "100"
    jitter: 50ms
  selector:
    namespaces: [my-app]
  duration: 5m
```

**What it tests:** Timeouts, retries, slow downstream handling.

**Steady state:** App has timeouts. Doesn't pile up requests. Returns errors instead of hanging.

**DNS failure**

```bash
# chaos-mesh
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: dns-failure
spec:
  mode: all
  selector:
    namespaces: [kube-system]
    labelSelectors:
      k8s-app: kube-dns
  stressors:
    dns:
      patterns:
        - "FAIL\0"
      probability: 100
```

**What it tests:** DNS retry, caching, fallback to IPs.

### Tier 3: Node-level

**Drain a node**

```bash
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data
```

**What it tests:** PDBs, graceful shutdown, pod rescheduling, anti-affinity.

**Steady state:** Pods reschedule to other nodes. No data loss. Brief latency increase.

**Hypothesis:** "If a node is drained, pods move to other nodes within 2 minutes, no pods are stuck terminating."

**Kill a kubelet**

```bash
ssh node-1
sudo systemctl stop kubelet
```

**What it tests:** Node controller timeout, PLEG, pod rescheduling.

**Steady state:** Node marked NotReady within 5 minutes, pods rescheduled.

**Network partition a node**

```bash
# using iptables on the node
sudo iptables -A INPUT -s <other-nodes> -j DROP
# or using chaos-mesh NetworkChaos with action: partition
```

**What it tests:** Network resilience, what happens when a node can't reach the apiserver.

### Tier 4: Cluster-level

**Kill the apiserver**

The hardest one. Disrupts all cluster operations.

```bash
# on a master node
sudo systemctl stop kube-apiserver
```

**What it tests:** Existing pods keep running. New pods can't be scheduled.

**Steady state:** Existing pods continue serving. After 5 minutes, node controller marks nodes NotReady.

**⚠️ Don't do this in production without a controlled test environment.**

**etcd failure**

```bash
# on an etcd node
sudo systemctl stop etcd
```

**What it tests:** etcd quorum loss, apiserver behavior, data consistency.

**Steady state:** With 3 etcd nodes, losing 1 keeps quorum. With 5, losing 2 still works.

### Tier 5: Application-level

**Corrupt the database**

Drop a table, kill a transaction, replicate a bad row.

**What it tests:** App's error handling, data validation, recovery.

**Hypothesis:** "If the database returns an error, the app returns 5xx to the user, doesn't crash, recovers when DB is back."

**Slow down the database**

Add latency to DB queries.

**What it tests:** App's DB timeouts, connection pool behavior, query timeouts.

**Steady state:** App times out DB calls, doesn't pile up requests, returns errors fast.

## The tools

### Chaos Mesh

CNCF project. Most common in k8s.

```bash
# install
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh --create-namespace

# a stresschaos experiment
kubectl apply -f - <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: pod-cpu-stress
  namespace: chaos-mesh
spec:
  mode: all
  selector:
    namespaces: [my-app]
    labelSelectors:
      app: web
  stressors:
    cpu:
      workers: 2
      load: 80
  duration: 5m
EOF
```

**Capabilities:** pod failure, network partition, latency, DNS, IO, time skew, stress (CPU/memory/IO), kernel-level (kill, panic).

### Litmus

Another CNCF chaos engineering tool.

```bash
# install
kubectl apply -f https://litmuschaos.github.io/litmus/litmus-operator-v3.0.0.yaml
# or via Helm

# run an experiment
kubectl apply -f https://hub.litmuschaos.io/api/chaos/3.0.0?file=charts/generic/pod_delete/experiment.yaml
```

**Capabilities:** pre-built experiments, observability, chaos workflow.

### Gremlin (commercial)

Hosted chaos engineering platform. More polished UX.

```bash
# install the Gremlin agent
helm install gremlin gremlin/gremlin \
  --set gremlin.secret.managed=true \
  --set gremlin.teamID=<your-team-id>
```

**Capabilities:** all of the above, plus stateful attacks, network conditions, host-level.

### Litmus vs Chaos Mesh vs Gremlin

| Tool | Cost | Pre-built exp | UI | Production use |
|------|------|---------------|-----|---------------|
| **Chaos Mesh** | Free | Many | Web UI | Yes |
| **Litmus** | Free | Many | Web UI | Yes |
| **Gremlin** | $$$ | Many | Web UI | Yes |
| **Steadybit** | $$$ | Many | Web UI | Yes |

For most teams, **Chaos Mesh** is the right balance. Free, comprehensive, well-maintained.

## Game days

A **game day** is a planned chaos exercise. The team gathers, runs experiments, observes, and learns.

**Run quarterly.** Set aside 4 hours. Have an agenda:

1. **Hypothesis presentation** — "we believe X" (15 min)
2. **Baseline measurement** — confirm steady state (15 min)
3. **Experiments** — run 3-5 chaos scenarios (90 min)
4. **Findings** — what broke, what surprised us (45 min)
5. **Action items** — fix the things we found (30 min)
6. **Post-mortem** — what did we learn (15 min)

**Run in staging first** if you have one. Production if you don't, with a controlled blast radius.

**Have a "stop" button.** The person running the experiment should have the ability to abort everything if it goes wrong.

## Continuous chaos

After a few game days, automate the experiments. **Chaos experiments should run continuously** in production, with safe defaults.

```yaml
# example: a scheduled experiment
apiVersion: chaos-mesh.org/v1alpha1
kind: Schedule
metadata:
  name: weekly-pod-kill
spec:
  schedule: "0 14 * * 1"   # every Monday 2pm
  type: PodChaos
  historyLimit: 5
  concurrencyPolicy: Forbid
  podChaos:
    action: pod-kill
    mode: one
    selector:
      namespaces: [staging]
      labelSelectors:
        app: web
```

**Steady state monitoring:**

```yaml
# Prometheus alert
- alert: ChaosExperimentBrokeSteadyState
  expr: |
    (
      sum(rate(http_requests_total{status=~"5.."}[5m])) /
      sum(rate(http_requests_total[5m]))
    ) > 0.01
  for: 5m
  annotations:
    summary: "Error rate spiked during chaos experiment"
```

If the experiment breaks the steady state, the alert fires, the experiment should be aborted (or auto-aborted by the tooling).

## The blast radius

Start small. Expand as you gain confidence.

| Phase | Experiment | Blast radius |
|-------|------------|--------------|
| 1 | Kill 1 pod of non-critical service | 1 pod, 1 service |
| 2 | Kill 1 pod of critical service | 1 pod, but monitoring on it |
| 3 | Drain 1 node | 1 node, but only in staging |
| 4 | Network partition between 2 services | 2 services, in staging |
| 5 | Kill all pods in a Deployment (one at a time) | 1 Deployment, in staging |
| 6 | Drain a node in production | 1 node, with monitoring |
| 7 | Zone failure simulation | 1 zone, with traffic shifting |
| 8 | Region failure simulation | 1 region, with DR invocation |

**Always have a rollback plan.** If the experiment goes sideways, how do you recover in 5 minutes?

## Steady state hypotheses

Some good starting hypotheses:

| Experiment | Hypothesis |
|------------|------------|
| Kill 1 pod | "Replicas reduce to 4, no error rate spike, no data loss." |
| Kill all pods of a service | "Service comes back within 2 min, error rate spike <5%, no cascading failures." |
| Add 500ms latency between services | "P99 latency increases by 500ms, error rate stays the same, timeouts trigger correctly." |
| Drain a node | "Pods reschedule to other nodes within 5 min, no PDB violations." |
| Network partition between 2 services | "Circuit breaker triggers, calls fail fast, system recovers when partition heals." |
| OOMKill a pod | "Pod restarts with same memory, OOM kill is recorded, no cascading OOMs." |
| CPU stress to 100% | "Pod is throttled, no others affected (CPU limits work), throttling visible in metrics." |

Each hypothesis should be **specific** and **measurable**.

## The "is this chaos or just a real outage?" question

In production, chaos experiments blend with real failures. Three ways to tell:

1. **Mark experiments clearly.** Use labels, tags, or chaos-specific namespaces.
2. **Log experiments in the chaos platform.** Gremlin, Chaos Mesh, etc. all log experiments.
3. **Run experiments in pairs.** If the experiment broke something, the team knows. If something else broke, the experiment's silent.

**Don't hide chaos experiments.** If you're running them, the team should know.

## Common gotchas

* **Chaos in production requires buy-in.** SRE, engineering, leadership. Don't surprise people.
* **Steady state must be measurable.** If you can't measure it, chaos is theater.
* **The first experiment always reveals something.** Be ready to learn and fix.
* **Don't run experiments on critical services without monitoring.** Always have observability before breaking things.
* **Network partitions are hard to clean up.** Some chaos tools leave iptables rules behind. Verify the cleanup.
* **The "stop" button is critical.** Have someone who can abort all experiments in seconds.
* **Game days require prep.** Walk through the experiments mentally before running them.
* **Some experiments require permissions you don't have.** Killing kubelet, restarting etcd — you might not have SSH access in production. Use chaos tools that work via the k8s API.
* **Chaos Mesh / Litmus / Gremlin have their own blast radius.** Their pods have permissions to do harmful things. Restrict with RBAC.
* **Continuous chaos in production is advanced.** Start with game days, automate slowly.

## A worked example

**Goal:** Validate that the checkout service can survive a downstream (payment gateway) latency spike.

**Hypothesis:** "If the payment gateway returns in 2s instead of 100ms, the checkout service times out after 1s, returns a 503 to the user, and recovers when the latency is removed."

**Setup:**
1. Define steady state: P99 latency <500ms, error rate <0.1%, no failed transactions
2. Install chaos-mesh in staging
3. Run NetworkChaos to add 2s latency to payment-gateway traffic
4. Run for 10 minutes
5. Monitor: latency, error rate, transaction success rate
6. Compare against steady state

**Run the experiment:**

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: payment-latency
  namespace: chaos-mesh
spec:
  action: delay
  delay:
    latency: 2s
    correlation: "100"
    jitter: 0
  selector:
    namespaces: [prod]
    labelSelectors:
      app: payment-gateway
  direction: to
  duration: 10m
```

**Observe:**

```
T+0min:  Latency 100ms, errors 0.05%
T+2min:  Latency 200ms, errors 0.08%   (system starting to feel pressure)
T+5min:  Latency 800ms, errors 0.5%    (some timeouts triggering)
T+8min:  Latency 1100ms, errors 2%     (circuit breaker should trigger)
T+10min: Chaos ends
T+12min: Latency 100ms, errors 0.05%   (recovered)
```

**Findings:**

- ✅ Timeouts trigger correctly
- ✅ Circuit breaker engaged at 1s (config working)
- ✅ Recovery is fast (within 2 min of chaos ending)
- ❌ Some users saw 503s during the experiment (acceptable for partial outage, but not great)
- ❌ No graceful degradation — users had to retry

**Actions:**

- Improve user-facing error message ("Payment processing slow, please try again")
- Add a circuit breaker at the frontend (BFF pattern)
- Increase timeout to 1.5s for better tolerance

**Re-test in 2 weeks** to validate fixes.

## The "blast radius" for chaos

**Always start small.** A chaos experiment that takes down a critical service is not a learning experience — it's an outage.

| Blast radius | When to use |
|--------------|-------------|
| **1 pod, non-critical** | First day of chaos |
| **1 pod, critical** | After 5+ non-critical experiments |
| **1 node, dev** | After 10+ pod experiments |
| **1 node, prod** | After 5+ node experiments in dev |
| **All pods of a service** | After 20+ pod experiments |
| **Network partition** | After node experiments |
| **Zone failure** | Game day, multiple teams observing |
| **Region failure** | Once a year, full team |

## The chaos experiment template

Every chaos experiment should have:

```yaml
# a ChaosExperiment manifest
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: web-pod-kill
  namespace: chaos-mesh
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces: [my-app]
    labelSelectors:
      app: web
  duration: 1m
  # what to verify
  # - service stays healthy (4+ backends)
  # - error rate <0.1%
  # - no data loss
```

**Hypothesis** (write this down before running):

> "If 1 of 5 web pods is killed, the Service will have 4 backends within 10s. Error rate will briefly spike to <1%, returning to <0.1% within 30s. No requests will be lost (load balancer retries to healthy backends)."

**Run the experiment. Compare against hypothesis. Document findings.**

## Steady state metrics

The metrics you watch during chaos:

- **Pod restarts** (`kube_pod_container_status_restarts_total`)
- **Endpoint availability** (`kube_endpoint_address_available`)
- **Service backend count** (custom, scrape from the Service)
- **HTTP error rate** (5xx, 4xx, by status code)
- **Request latency** (p50, p95, p99)
- **Saturation** (CPU, memory, network, IO)
- **Custom business metrics** (orders/sec, queue depth)

```yaml
# Prometheus alerts for chaos experiments
- alert: ErrorRateDuringChaos
  expr: |
    sum(rate(http_requests_total{status=~"5.."}[1m])) /
    sum(rate(http_requests_total[1m]))
    > 0.05
  for: 1m
  annotations:
    summary: "Error rate above 5% during chaos experiment"

- alert: LatencyDuringChaos
  expr: |
    histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[1m]))
    > 1.0
  for: 1m
  annotations:
    summary: "P99 latency above 1s during chaos"
```

If any of these fire during chaos, you found a problem.

## Common chaos scenarios (organized by attack vector)

### Compute

- **Pod kill** — kubelet restarts the pod
- **Pod failure** (OOM, segfault) — test memory limits
- **CPU stress** — test CPU limits and QoS
- **Memory stress** — test OOM handling
- **IO stress** — test disk pressure handling
- **Process kill** (specific PIDs) — test error handling

### Network

- **Network partition** — split brain scenarios
- **Latency** — slow downstream
- **Packet loss** — degraded network
- **DNS failure** — name resolution issues
- **Bandwidth limit** — saturated network
- **Corrupt packets** — bad network paths

### Storage

- **Disk fill** — full disk
- **IO error injection** — bad blocks
- **PVC delay** — slow attach
- **Snapshot failure** — backup issues

### Time

- **Clock skew** — NTP issues, certificate failures
- **Time travel** — leap seconds, daylight saving

### State

- **Database crash** — failover testing
- **Cache eviction** — cold cache
- **Connection pool exhaustion** — DB connection issues
- **Queue depth spike** — sudden load

### External

- **Cloud API failure** — IAM, EC2, S3 unreachable
- **DNS provider down** — public DNS issues
- **Registry unavailable** — can't pull images

## Chaos as code

Write chaos experiments as code, version controlled:

```
chaos/
├── README.md
├── pod-level/
│   ├── kill-pod.yaml
│   ├── oom-pod.yaml
│   └── cpu-stress.yaml
├── network/
│   ├── partition.yaml
│   ├── latency.yaml
│   └── packet-loss.yaml
├── storage/
│   ├── disk-fill.yaml
│   └── io-error.yaml
└── advanced/
    ├── zone-failure.yaml
    └── region-failure.yaml
```

Each file is a Chaos Mesh (or Litmus) experiment. Reuse, version, share.

## The 5 phases of a chaos program

### Phase 1: Foundations (months 1-2)

- Set up the chaos tool (Chaos Mesh, Litmus, Gremlin)
- Run experiments in dev only
- Document findings
- Build the team's confidence

### Phase 2: Game days (months 3-4)

- Quarterly game days
- Multiple teams involved
- Documented runbooks
- Tabletop exercises

### Phase 3: Scheduled experiments (months 5-6)

- Move experiments to cron
- Run in staging weekly
- Production experiments manually approved

### Phase 4: Continuous chaos (months 7-9)

- Experiments run automatically in production
- Auto-abort on steady-state violations
- Real-time observability

### Phase 5: Chaos-driven development (months 10+)

- Every new feature gets a chaos test
- Pre-merge validation
- Production-readiness reviews include chaos

## The "what broke" report

After every experiment, write up what you learned:

```markdown
# Experiment: Kill 1 web pod
Date: 2024-01-15
Hypothesis: Service stays healthy with 4 backends

## What we observed
- 4 backends within 8s (expected 10s) ✓
- Error rate: 0.5% spike for 5s, returned to 0.05% (expected <0.1%) ✓
- No data loss ✓

## What surprised us
- Readiness probe was 30s, not the 10s we thought
- PDB was not configured (was set to 0 from a previous test)
- HPA was at minReplicas=2, but only because we set it manually

## Action items
- [ ] Fix readiness probe interval (now 10s)
- [ ] Set PDB minAvailable=2 (was 0)
- [ ] Verify HPA minReplicas in production manifest
```

**This is the most valuable output of chaos engineering.** The findings drive improvements.

## The 3am chaos experiment

Once you're running continuous chaos, you'll have an experiment fire at 3am. **Make sure:**

- The experiment is **labeled clearly** as chaos (not real outage)
- The team knows how to **distinguish chaos from real**
- The auto-abort works (or the on-call knows to abort)
- The on-call rotation is **aware of the chaos schedule**

**Surprise 3am experiments are bad.** Communicate clearly.

## See also

* [[Kubernetes/guides/non-functional/high-availability|high-availability]] — what to test
* [[Kubernetes/guides/non-functional/disaster-recovery|disaster-recovery]] — broader failure modes
* [[Kubernetes/guides/troubleshooting/node-not-ready|node-not-ready]] — real-world failure
* [Principles of Chaos](https://principlesofchaos.org/)
