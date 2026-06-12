---
title: Progressive Delivery Strategies
tags:
  - Kubernetes
  - Delivery
  - Progressive-Delivery
  - Canary
  - Blue-Green
  - A/B Testing
---

Progressive delivery = **deploy to a subset of users, observe, gradually expand**. The opposite of big-bang releases. Strategies: rolling update, canary, blue-green, A/B, feature flags, shadow. **Pick the right one for the risk.**

## The strategies at a glance

| Strategy | Traffic split | Rollback speed | Complexity | Best for |
|----------|---------------|----------------|------------|----------|
| **Recreate** | 0/100 → 100/0 | Slow (full restart) | Low | Dev only |
| **Rolling update** | Gradual | Slow (drain) | Low | Stateless services |
| **Canary** | 1% → 5% → 25% → 100% | Fast (route back) | Medium | Risky changes |
| **Blue-green** | 0/100 → 100/0 (atomic) | Instant (route back) | Medium | Schema changes |
| **A/B** | Header-based split | Fast (route back) | Medium-High | UX experiments |
| **Shadow** | 100% (live) + 100% (canary, no response) | N/A (no impact) | High | Performance testing |
| **Feature flags** | 100% (with code toggle) | Instant (toggle) | Low-Medium | Continuous deploy |

## 1. Recreate

```yaml
spec:
  strategy:
    type: Recreate
```

Kill all old pods. Start all new. **Downtime.** Dev only.

## 2. Rolling update (default)

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%       # can have 25% more pods during rollout
      maxUnavailable: 0   # zero downtime
```

One at a time (or batches), replace old with new. Default in Deployments. Works for stateless services with backward-compatible changes.

**Risk:** mixed versions serve traffic. A new pod serves alongside an old one. If the change is breaking (e.g., schema), this can corrupt data.

**Rollback:** slow. `kubectl rollout undo` triggers another rolling update.

## 3. Canary

**Concept:** route 1-5% of traffic to the new version. If metrics are good, expand. If bad, route 0%.

```yaml
# argo-rollouts canary
spec:
  strategy:
    canary:
      steps:
      - setWeight: 1      # 1% canary
      - pause: {duration: 5m}
      - setWeight: 10
      - pause: {duration: 10m}
      - setWeight: 50
      - pause: {duration: 10m}
      - setWeight: 100
      canaryService: my-app-canary
      stableService: my-app-stable
```

**How it works:** two Services, one for stable, one for canary. The Rollout controller shifts traffic (via L7 or Service weight).

**When to use:** risky changes (schema, infra, new dependency). You want to see real traffic impact before going full.

**Pros:** real users, real metrics, can stop early.

**Cons:** users on canary see new version, so they can have a bad experience briefly.

**Rollback:** fast. Just `setWeight: 0`.

## 4. Blue-green

**Concept:** new version deployed alongside. Switch traffic atomically. If new is bad, switch back.

```yaml
spec:
  strategy:
    blueGreen:
      activeService: my-app-active
      previewService: my-app-preview
      autoPromotionEnabled: false   # manual promotion
      previewReplicaCount: 100%
```

**Two Services:**
- `my-app-preview` → new (green) version
- `my-app-active` → current (blue) version

**Test:** hit `my-app-preview` to test new version. Production traffic is on `my-app-active`.

**Promote:** switch `my-app-active` to point to green.

**When to use:** schema changes (e.g., DB migration), risky infra changes, instant rollback.

**Pros:** zero-downtime, instant rollback, easy to test in production.

**Cons:** 2x resources during deploy, requires careful Service management.

**Variations:**
- **Blue-green + smoke tests:** run tests against preview, only promote on success
- **Blue-green + canary:** run preview with internal users, promote to all

## 5. A/B testing

**Concept:** route by header / cookie / user attribute. Compare metrics across versions.

```yaml
# istio VirtualService
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  http:
  - match:
    - headers:
        x-experiment:
          exact: "new-checkout"
    route:
    - destination:
        host: my-app-v2
  - route:
    - destination:
        host: my-app-v1
      weight: 100
```

**Users with `X-Experiment: new-checkout` header get v2. Others get v1.**

**When to use:** UX experiments, testing new features with specific user segments, comparing conversion rates.

**Pros:** controlled rollout, real user feedback, no full switch.

**Cons:** requires mesh/ingress with header routing, analysis is complex.

**Common patterns:**
- **Internal users** get canary (`X-Employee: true`)
- **Beta opt-in** users get canary (`X-Beta: true`)
- **Geographic** split (by IP / country)
- **Random sampling** (10% of users)

## 6. Shadow traffic

**Concept:** new version gets a copy of production traffic, but doesn't return the response.

```yaml
# istio
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  http:
  - route:
    - destination:
        host: my-app-v1
      weight: 100
    - destination:
        host: my-app-v2
      weight: 100    # also gets all traffic
    mirror:
      host: my-app-v2
```

**Wait, this is broken.** Mirror sends a copy to v2, response is discarded. v1 still returns the real response.

```yaml
# correct mirror
spec:
  http:
  - route:
    - destination:
        host: my-app-v1
    mirror:
      host: my-app-v2
      # 100% of v1's traffic is mirrored to v2
```

**When to use:** testing new version with production load, performance testing, validating behavior change.

**Pros:** no user impact (real traffic, but no response change), validates with real load.

**Cons:** requires careful isolation (the canary can still write to DBs, send emails, etc. — be careful!).

**Critical:** the shadow can't have side effects. No DB writes, no emails, no external calls. Use a "shadow mode" in the app code or a service mesh that drops side effects.

## 7. Feature flags

**Concept:** deploy 100% of code, but the new feature is hidden behind a flag. Toggle on for users.

```python
if feature_flag.is_enabled("new-checkout", user):
    new_checkout_flow()
else:
    old_checkout_flow()
```

**Tools:**
- **LaunchDarkly** — commercial
- **Unleash** — open source, self-hosted
- **Flagsmith** — open source + commercial
- **OpenFeature** — CNCF, vendor-neutral
- **Split.io** — commercial

**When to use:** every deploy. Toggles for risky features, experiments, ops killswitches.

**Pros:** instant rollback (toggle off), canary by user, A/B built in.

**Cons:** requires app code change, technical debt if flags are never removed.

**Best practice:** have a flag lifecycle. Every flag has an owner and a removal date. Track flag count.

## The decision tree

```
Q: Is this a risky change?
│
├── No  (config, low-impact feature)
│    └── Rolling update (default)
│
└── Yes
    │
    Q: Can users tolerate a bad experience briefly?
    │
    ├── Yes
    │    └── Canary (1% → 100%)
    │
    └── No  (critical, must not have bad users)
         │
         Q: Need to test with real load first?
         │
         ├── Yes
         │    └── Shadow traffic
         │
         └── No
              │
              Q: Can you switch atomically?
              │
              ├── Yes  (no schema break)
              │    └── Blue-green
              │
              └── No  (need to test in production)
                   └── Blue-green with manual smoke tests
```

## The metrics to watch

For any progressive delivery, monitor:

### Application metrics

- **Error rate** (5xx) per version
- **Latency** (p50, p95, p99) per version
- **Saturation** (CPU, memory, queue depth) per version

### Business metrics

- **Conversion** (signup, purchase, etc.) per version
- **Revenue** per version
- **User engagement** per version

### System metrics

- **Pod restarts** per version
- **Crash loops** per version
- **Health check failures** per version

**Comparison: canary vs stable.** If canary error rate is 2x stable, abort. If canary latency is 1.5x stable, consider aborting.

## The rollback decision

When to abort and rollback:

- **Hard signals:** error rate spike, latency spike, OOM, crash loops
- **Soft signals:** slower deploys, higher resource use, unusual metrics

**For soft signals:** wait, observe. They might be transient.

**For hard signals:** abort immediately. Better to lose 1% of traffic than 100%.

**Automated rollback:** Argo Rollouts / Flagger with analysis templates. If error rate > 5%, abort and rollback.

## The "stuck" rollout

If a canary is at 50% and you can't decide:

- **Continue if:** metrics are ambiguous but no clear failure
- **Abort if:** any sign of trouble, even minor
- **Pause indefinitely if:** you need more data (manual gate)

A "stuck" canary is a deploy that's not moving forward. Either you promote it or you abort. Don't leave it.

## Multi-cluster progressive delivery

For multi-region, progress can be:

- **Per-region:** canary in `us-east-1` first, then `us-west-2`, then `eu-west-1`
- **Active-passive:** canary in passive region, then promote to active
- **Active-active:** canary in both regions simultaneously, monitor

Each region has its own risk profile. A canary in one region is half the risk.

## Common gotchas

* **Mixed versions during a rollout** can have issues. The new code expects a new schema, but old code reads it. Plan for backward compat.
* **DB migrations** are the trickiest part. Run the migration BEFORE the rollout, or use expand-contract (add column, deploy code, remove column).
* **Connection pools / caches** can have stale state. Roll the cache, restart the pool.
* **Logs and metrics** need to be tagged by version. Use a label.
* **Traces** must propagate across versions. Use W3C trace context.
* **Background workers** (cron, queues) need careful rollout. A worker that started on v1 might still be running on v1 after v2 deploys.
* **Stateful services** (DBs) can't do canary easily. Use blue-green or feature flags.
* **WebSockets / long-lived connections** are tricky. New connections get the new version, old stay on old.
* **The "long tail" of canary metrics** is real. Some metrics only show bad behavior after 1 hour, not 5 minutes.
* **Regional differences** matter. A canary in us-east-1 might pass while failing in ap-southeast-1 (different latency, different users).

## A worked example

**Goal:** roll out a new checkout flow with minimal risk.

**Strategy:** Feature flag + canary + analysis.

1. **Deploy code with flag off** (100% old flow)
2. **Internal users only** (1% with `X-Employee: true` header)
3. **Watch metrics** for 1 hour
4. **Enable for 1% of all users**
5. **Watch metrics** for 1 hour
6. **Expand to 10%, 25%, 50%** with metrics gates
7. **Full rollout** to 100%

**Metrics watched:**
- Conversion rate (purchase / visit)
- Cart abandonment rate
- Error rate
- Latency (p50, p99)
- Customer support tickets

**Auto-abort:** if error rate > 5% or conversion drops > 10%, kill the flag.

**Rollback plan:** flip the flag off. Instant. (This is why we use flags.)

## Detailed strategy comparisons

### Rolling update: when it works, when it doesn't

Rolling update is the simplest and works for most stateless services. The pattern:

```
T+0:  3 v1 pods, 0 v2 pods
T+1:  2 v1 pods, 1 v2 pods (start v2)
T+2:  1 v1 pod, 2 v2 pods
T+3:  0 v1 pods, 3 v2 pods (drain v1)
T+4:  3 v2 pods
```

**The good:**
- Built into Deployment, no extra tooling
- Resource-efficient (just enough extra pods)
- No mesh or ingress changes

**The bad:**
- Mixed versions during rollout (can corrupt data with breaking changes)
- Hard to monitor (which version did this request go to?)
- Slow rollback (~minutes)

**When to use:** stateless services, backward-compatible changes, no DB schema changes.

**When not to use:** stateful services, breaking API changes, anything where the old version reads what the new version writes.

### Canary: the most common progressive pattern

Canary is the workhorse of progressive delivery. The new version is exposed to a small percentage of traffic, expanded if metrics are good.

```
T+0:  v1 gets 100% traffic, v2 gets 0%
T+1:  v1 gets 95%, v2 gets 5%
T+5:  v1 gets 50%, v2 gets 50%   (after metrics check)
T+10: v1 gets 0%, v2 gets 100%   (after final check)
```

**The good:**
- Real user traffic, real metrics
- Can stop early (small % affected)
- L7 routing (Istio, Linkerd, ingress) for true % splitting

**The bad:**
- Some users get the bad version
- Requires L7 infrastructure
- Metrics need to be per-version (extra labeling)

**When to use:** risky changes where you want real user feedback but want to limit blast radius.

**The "5% to 100%" duration:** typically 30 minutes to 4 hours. The first 5-10 minutes catches obvious issues, the next 30 minutes catches subtle ones.

### Blue-green: the safest switch

Blue-green deploys the new version alongside, then switches traffic atomically.

```
T+0:  v1 (blue) gets 100% traffic, v2 (green) is idle
T+1:  v2 (green) deployed, can be tested via preview
T+5:  v2 (green) gets 100% traffic (after smoke test)
T+10: v1 (blue) scaled down (after cooldown)
```

**The good:**
- Instant rollback (switch back to blue)
- New version can be tested in production (preview service)
- No mixed versions in production

**The bad:**
- 2x resources during deploy
- Two Services to manage
- DB migration timing is critical (old code can break new schema)

**When to use:** schema changes, risky infrastructure changes, when rollback speed is critical.

**The DB migration problem:** if v2 expects a new column, v1 must not break with the new column. Use the expand-contract pattern:

1. **Expand:** add the new column (both versions can read/write)
2. **Migrate:** deploy v2 (now writes to both old and new columns)
3. **Contract:** remove the old column (only v2 supports it)

### A/B testing: the data-driven approach

A/B is for **learning**, not just deploying. Two versions live indefinitely, and the route is split by user attribute.

**The good:**
- Real user feedback on UX changes
- Statistical comparison
- Can run for weeks

**The bad:**
- Requires user attribution (cookie, user ID)
- Two versions always running (resource cost)
- Analysis is complex (need statistics)

**When to use:** UX changes, business experiments, feature adoption testing.

**A/B test design:**
- Hypothesis: "new checkout increases conversion by 5%"
- Control: 50% of users, current checkout
- Treatment: 50% of users, new checkout
- Metric: conversion rate
- Duration: 1-2 weeks (or until statistical significance)

### Shadow traffic: the no-risk test

Shadow sends real traffic to a new version without affecting the response. The new version "sees" the traffic, but its response is discarded.

**The good:**
- No user impact
- Real production load (best test possible)
- Performance validation

**The bad:**
- The shadow can still have side effects (DB writes, emails, etc.)
- Requires careful isolation
- Doesn't validate UX (response isn't returned)

**Critical isolation pattern:** the shadow service must not have side effects. Either:
- App code has a "shadow mode" that disables side effects
- Service mesh drops side-effect calls
- The shadow uses a different database (or mocked)

**When to use:** major infra changes, performance validation, schema migration testing.

### Feature flags: continuous deploy

Feature flags decouple deploy from release. Code is deployed but feature is hidden.

**The good:**
- Instant toggle (roll back in milliseconds)
- Per-user targeting
- Trunk-based development friendly
- Can A/B test without service mesh

**The bad:**
- Code complexity (every feature has a flag)
- Flag debt (forgotten flags)
- App-level, not infra-level

**When to use:** every deploy. Flags for risky features, ops killswitches, experiments.

**Flag lifecycle:**
1. **Create:** flag added to code, off by default
2. **Enable:** flag on for internal/beta
3. **Roll out:** flag on for % of users
4. **Full:** flag on for all
5. **Remove:** code path removed, flag deleted

**Track all flags.** Have a flag owner. Have a removal date.

## The expansion automation

For canary, the roll-out can be:
- **Manual:** engineer watches metrics, promotes when ready
- **Scheduled:** 1% at 10am, 10% at 11am, 100% at noon
- **Metric-driven:** promote when error rate < X, latency < Y
- **Time-based:** promote after N minutes of steady state

**Metric-driven is the most robust.** Argo Rollouts analysis templates, Flagger metrics, Spinnaker pipelines.

```yaml
# argo-rollouts analysis
- analysis:
    templates:
    - templateName: success-rate
    args:
    - name: service-name
      value: my-app
```

The analysis queries Prometheus (or other), compares against thresholds, decides.

## The "promote or abort" decision

| Signal | Action |
|--------|--------|
| Error rate spike > 5% | **Abort** |
| Error rate 2-5% higher than stable | **Pause, investigate** |
| Error rate 1-2% higher | **Watch, continue if trending down** |
| Error rate same or lower | **Continue** |
| Latency spike > 50% | **Abort** |
| Latency 20-50% higher | **Pause, investigate** |
| Conversion drops > 10% | **Abort** |
| Conversion drops 5-10% | **Pause, investigate** |
| No signal | **Continue if scheduled, pause if not** |

**Default to abort.** False positives (unnecessary aborts) are cheap. False negatives (missed issues) are expensive.

## The "blast radius" question

How many users are affected by a canary issue?

| Stage | % users | ~Affected (1M users) |
|-------|---------|---------------------|
| 1% canary | 10,000 | 1 hour, 10k users |
| 5% canary | 50,000 | 1 hour, 50k users |
| 10% canary | 100,000 | 1 hour, 100k users |
| 50% canary | 500,000 | 1 hour, 500k users |
| 100% | 1,000,000 | 1 hour, all users |

If a canary issue is detected at 5%, blast radius is 50k. Detected at 100%, blast radius is 1M.

**Smaller canaries = smaller blast radius.** Start at 1-5%, not 25%.

## See also

* [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|argo-rollouts]] — the implementation
* [[Kubernetes/guides/delivery/gitops/basics|gitops-basics]] — the controller model
* [[Kubernetes/guides/non-functional/chaos-engineering|chaos-engineering]] — testing the system
* [Progressive Delivery book](https://www.progressive-delivery.com/) (free)
