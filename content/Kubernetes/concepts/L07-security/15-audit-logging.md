# Audit Logging

*"https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/"*

**Audit logging** is the apiserver's mechanism for **recording every request** that comes in: who made it, what they did, what the result was, where it came from. It's the **forensic record** of cluster activity — what the audit log doesn't show can't be investigated. Without audit logging, a breach leaves no trail. With it, every kubectl call, every admission, every API access is captured.

### Table of Contents

1. [What Audit Logging Solves](#1-what-audit-logging-solves)
2. [The Audit Log Event](#2-the-audit-log-event)
3. [The Audit Policy](#3-the-audit-policy)
4. [The Log Levels (None / Metadata / Request / RequestResponse)](#4-the-log-levels-none--metadata--request--requestresponse)
5. [The Stages](#5-the-stages)
6. [OmitStages and OmitManagedFields](#6-omitstages-and-omitmanagedfields)
7. [The Audit Backends](#7-the-audit-backends)
8. [The Log Backend (the default)](#8-the-log-backend-the-default)
9. [The Webhook Backend](#9-the-webhook-backend)
10. [Audit and AuthN/AuthZ/Admission](#10-audit-and-authnauthzadmission)
11. [Volume of Audit Logs](#11-volume-of-audit-logs)
12. [Shipping Audit Logs](#12-shipping-audit-logs)
13. [Audit Log Analysis](#13-audit-log-analysis)
14. [Operations and Debugging](#14-operations-and-debugging)
15. [Gotchas and Common Mistakes](#15-gotchas-and-common-mistakes)

---

## 1. What Audit Logging Solves

Audit logging answers:

* **Who** did what?
* **When** did they do it?
* **From where** (IP, user agent)?
* **What** was the result (allow / deny / error)?
* **What** did the request look like (the body)?

Use cases:

* **Forensics** — investigating a breach. "What did alice do at 3am?"
* **Compliance** — PCI-DSS, SOC2, HIPAA require audit logs.
* **Detection** — SIEM rules: "alert on multiple failed auth attempts".
* **Operational debugging** — "who deleted that Pod?"

What audit logging does NOT do:

* **Prevent** — audit logs are passive. They don't block anything. (Admission controllers, RBAC, NetworkPolicy do that.)
* **Detect in real time** — audit logs are records, not alerts. The SIEM does detection.
* **Encrypt secrets** — the request body is in the log. If the log is compromised, secrets are exposed.

## 2. The Audit Log Event

Each API request produces an `Event` object. The shape:

```json
{
  "kind": "Event",
  "apiVersion": "audit.k8s.io/v1",
  "level": "RequestResponse",
  "auditID": "abc-123-def",
  "stage": "ResponseComplete",
  "requestURI": "/api/v1/namespaces/default/pods",
  "verb": "create",
  "user": {
    "username": "alice",
    "groups": ["developers", "system:authenticated"]
  },
  "sourceIPs": ["10.0.0.5"],
  "userAgent": "kubectl/v1.30.0",
  "objectRef": {
    "resource": "pods",
    "namespace": "default",
    "name": "my-pod",
    "apiGroup": "",
    "apiVersion": "v1"
  },
  "responseStatus": {
    "metadata": {},
    "code": 201
  },
  "requestObject": {"spec": {...}},
  "responseObject": {"spec": {...}},
  "requestReceivedTimestamp": "2024-01-15T12:00:00.000Z",
  "stageTimestamp": "2024-01-15T12:00:00.123Z",
  "annotations": {
    "authorization.k8s.io/decision": "allow",
    "authorization.k8s.io/reason": "RBAC: allowed by ClusterRoleBinding \"cluster-admin\""
  }
}
```

Key fields:

* **`level`** — what was logged (Metadata, Request, RequestResponse).
* **`auditID`** — unique ID for the event. Use it to correlate logs across stages.
* **`stage`** — when the event was captured (RequestReceived, ResponseStarted, ResponseComplete, Panic).
* **`verb`** — the operation (create, update, delete, get, list, watch, etc.).
* **`user`** — who's making the request (from authn).
* **`objectRef`** — what the request targets.
* **`responseStatus`** — the result (HTTP status code).
* **`requestObject` / `responseObject`** — the full bodies (Request and RequestResponse levels).
* **`annotations`** — additional info from authn / authz / admission.

## 3. The Audit Policy

The audit policy is a YAML file passed to the apiserver via `--audit-policy-file`. It defines **what gets logged at what level**.

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets", "configmaps"]
  namespaces: ["prod"]
- level: Metadata
  resources:
  - group: ""
    resources: ["pods", "services"]
- level: None
  resources:
  - group: ""
    resources: ["events"]
  verbs: ["watch", "list"]
```

The policy is a **list of rules**. Each rule has a `level` and a match (resources, namespaces, verbs, users). The **first rule that matches** is used.

The default policy (in k8s source) logs everything at Metadata level.

### 3.1 The rule structure

```yaml
- level: RequestResponse
  # match criteria:
  resources: [...]              # resource types
  namespaces: [...]            # namespaces (empty = all)
  verbs: [...]                  # operations (create, update, delete, get, list, watch, ...)
  users: [...]                  # users (or SAs, e.g. "system:serviceaccount:...")
  userGroups: [...]             # OIDC groups
  nonResourceURLs: [...]       # for non-resource requests (e.g. /healthz)
  omitStages: [...]             # don't log at these stages
```

A rule can be as broad as "log everything at Metadata" or as narrow as "log this user's request to this specific resource at RequestResponse level".

### 3.2 The first-match-wins rule

The policy is **evaluated top-down**. The first rule that matches is used. Subsequent rules are ignored.

```yaml
rules:
- level: RequestResponse       # rule 1: matches Secrets
  resources:
  - group: ""
    resources: ["secrets"]
- level: Metadata              # rule 2: matches everything else (because rule 1 already matched Secrets)
  # no resources filter, so this matches anything that didn't match rule 1
```

A common pattern:

```yaml
rules:
- level: None                  # 1. don't log kube-system's noisy system components
  users: ["system:apiserver", "system:kube-controller-manager", ...]
- level: Metadata              # 2. log everything at Metadata (the default)
- level: RequestResponse       # 3. log Secrets at RequestResponse (override the default for these)
  resources: [{ group: "", resources: ["secrets"] }]
```

The order matters. Put **exceptions first** (None for noisy), then **defaults**, then **overrides** (RequestResponse for sensitive).

## 4. The Log Levels (None / Metadata / Request / RequestResponse)

| Level | What's logged |
|---|---|
| `None` | Nothing. The request is not logged. |
| `Metadata` | The request metadata: user, verb, URI, object ref, source IP, user agent. **Not the request or response body.** |
| `Request` | Metadata + the request body. |
| `RequestResponse` | Metadata + request body + response body. |

`RequestResponse` is the **most verbose** — it includes the response body, which is the created / updated object. For Pod creates, this is the full Pod spec. **For Secrets, this is the Secret's data.**

`Metadata` is the **safe default** for most resources. It's enough for forensics (who, what, when) without leaking sensitive data.

`RequestResponse` is needed for specific cases (e.g. "I want to know exactly what was created").

### 4.1 The volume trade-off

The volume of audit logs scales with the level:

* `None` — zero overhead.
* `Metadata` — a few hundred bytes per request. Low volume.
* `Request` — a few KB per request. Higher volume.
* `RequestResponse` — tens of KB to MB per request (for large objects). **Highest** volume.

For a busy cluster, `RequestResponse` on all resources can produce **gigabytes of audit logs per day**. The cost (storage, network to ship to a SIEM) is real.

The standard pattern:

* `RequestResponse` for **Secrets** (you need to know who accessed which secret).
* `RequestResponse` for **ConfigMaps in production** (if they have sensitive config).
* `Metadata` for **everything else** (Pods, Deployments, etc.).
* `None` for **system components** (kube-controller-manager, kube-scheduler, system SAs) — these generate massive volume.

## 5. The Stages

The apiserver emits events at multiple stages:

* **`RequestReceived`** — the moment the request comes in (before any processing).
* **`ResponseStarted`** — for long-running requests (watches), the first response.
* **`ResponseComplete`** — the request is complete (success or error).
* **`Panic`** — the apiserver panicked during processing.

`RequestReceived` and `ResponseComplete` are the standard. `ResponseStarted` is for streaming responses (watches). `Panic` is rare but should be alerted on.

By default, the apiserver emits at `ResponseComplete`. To get `RequestReceived` too:

```yaml
rules:
- level: Metadata
  resources: [...]
  # omitStages: ["RequestReceived"]  # to skip RequestReceived
```

Without `omitStages`, both `RequestReceived` and `ResponseComplete` are emitted for matched rules.

## 6. OmitStages and OmitManagedFields

### 6.1 `omitStages`

```yaml
- level: RequestResponse
  omitStages:
  - "RequestReceived"
```

The rule fires at `ResponseComplete` only, not at `RequestReceived`. This halves the volume for that rule (no duplicate events).

### 6.2 `omitManagedFields`

In the audit policy:

```yaml
- level: RequestResponse
  omitManagedFields: false     # default
```

`managedFields` is the `metadata.managedFields` field, populated by `server-side apply`. It can be **large** (every field's last applier). Setting `omitManagedFields: true` reduces volume at the cost of losing the apply history.

For most clusters, leave it `false` (default) and accept the volume.

## 7. The Audit Backends

The apiserver ships events to one or more **backends**:

* **`log`** — writes to a file on the apiserver's node.
* **`webhook`** — sends to an external HTTP endpoint.
* **`dynamic`** — uses a `AuditSink` CRD (newer).

The backends are configured via the apiserver's flags:

```bash
--audit-log-path=/var/log/kubernetes/audit/audit.log
--audit-log-maxage=30                # days
--audit-log-maxbackup=10
--audit-log-maxsize=100              # MB per file

--audit-webhook-config-file=/etc/kubernetes/audit-webhook-config.yaml
```

Multiple backends can be configured (log + webhook). The events are sent to all of them.

## 8. The Log Backend (the default)

```bash
--audit-log-path=/var/log/kubernetes/audit/audit.log
--audit-log-format=json             # or text
--audit-log-maxage=30
--audit-log-maxbackup=10
--audit-log-maxsize=100
```

The log backend writes events as JSON lines to a file. The file is **rotated** by the apiserver (max age, max size, max backups).

The default `format: json` is one event per line. Easier to parse and ship (Fluentd, Vector, etc.).

**The log backend is on the apiserver's local disk.** If the apiserver's host is compromised, the log is too. **Always ship to an external store.**

## 9. The Webhook Backend

```yaml
# /etc/kubernetes/audit-webhook-config.yaml
apiVersion: v1
kind: Config
clusters:
- name: my-sink
  cluster:
    server: https://audit-collector.example.com/audit
    certificate-authority: /etc/kubernetes/ca.crt
contexts:
- context:
    cluster: my-sink
    user: ""
  name: default-context
current-context: default-context
```

The apiserver sends events to the webhook's URL. The webhook is typically:

* A SIEM (Splunk, Elastic, Datadog).
* A custom collector (Fluentd, Vector, Falco Sidekick).
* A log aggregator (Loki, OpenSearch).

The webhook is a **batched, retried HTTP POST**. The apiserver buffers events and sends them in batches. If the webhook is down, the apiserver retries (with backoff). If the buffer fills, events are dropped (with a metric).

### 9.1 The audit policy rules for the webhook

The same policy applies to both backends. The level and the match are the same. The backend is just where the events go.

A common pattern:

* **Log backend** — keep for "what just happened" debugging (recent events on the apiserver's disk).
* **Webhook backend** — ship to a SIEM for long-term storage and analysis.

## 10. Audit and AuthN/AuthZ/Admission

The audit event records the **full request** through the pipeline:

* **AuthN result** — `user` field. If authn failed, the `user.username` is `system:anonymous` or `system:unauthenticated`, and `responseStatus.code` is 401.
* **AuthZ result** — `annotations["authorization.k8s.io/decision"]` and `reason`. "allow" or "forbid".
* **Admission result** — if admission rejected, `responseStatus.code` is 400-499 with the admission error in `responseObject.message`.

A successful CREATE looks like:

```json
{
  "level": "RequestResponse",
  "stage": "ResponseComplete",
  "verb": "create",
  "user": {"username": "alice", "groups": ["developers"]},
  "responseStatus": {"code": 201},
  "annotations": {
    "authorization.k8s.io/decision": "allow",
    "authorization.k8s.io/reason": "RBAC: allowed by RoleBinding \"devs\""
  }
}
```

A denied request:

```json
{
  "level": "RequestResponse",
  "verb": "create",
  "user": {"username": "alice", "groups": ["developers"]},
  "responseStatus": {"code": 403, "message": "User \"alice\" cannot create resource \"pods\"..."},
  "annotations": {
    "authorization.k8s.io/decision": "forbid",
    "authorization.k8s.io/reason": "RBAC: no rules permit..."
  }
}
```

A failed admission:

```json
{
  "level": "RequestResponse",
  "verb": "create",
  "user": {"username": "alice", "groups": ["developers"]},
  "responseStatus": {"code": 400, "message": "admission webhook denied: privileged container"},
  "annotations": {
    "authorization.k8s.io/decision": "allow",
    "authorization.k8s.io/reason": "RBAC: allowed",
    "mutatingwebhook.admission.k8s.io/decision": "allow",
    "validatingwebhook.admission.k8s.io/decision": "denied"
  }
}
```

The audit log captures the **full pipeline outcome**. SIEM rules can alert on:

* 401 (failed authn)
* 403 (failed authz)
* 400 with admission-related message (failed admission)
* Burst of failed requests (brute force)

## 11. Volume of Audit Logs

A busy cluster can produce **millions of audit events per day**. Rough estimates:

* A small cluster (10 services, 100 Pods, 5 users): ~1-10 MB/day at Metadata.
* A medium cluster (100 services, 1000 Pods, 50 users): ~10-100 MB/day at Metadata.
* A large cluster (1000 services, 10,000 Pods, 500 users): ~100 MB-1 GB/day at Metadata.
* With `RequestResponse` on Secrets: add 10-100% on top.

The system components are the **biggest source**:

* `kube-controller-manager` polls every object every few seconds (heartbeat updates).
* `kube-scheduler` watches Pods, Nodes.
* `kube-proxy` watches Services, Endpoints.
* CNI daemons watch Pods, Nodes.

Without a `users: [...]` filter for system components, the audit log is mostly these. The standard pattern is to **None them out**:

```yaml
- level: None
  users:
  - "system:apiserver"
  - "system:kube-controller-manager"
  - "system:kube-scheduler"
  - "system:serviceaccount:kube-system:generic-garbage-collector"
  # etc.
```

## 12. Shipping Audit Logs

Audit logs are typically shipped to a SIEM or log aggregator. The standard pattern:

```
apiserver
  │ writes to /var/log/kubernetes/audit/audit.log
  │
  ▼
DaemonSet (Fluentd / Vector / Filebeat) on control plane nodes
  │ tails the file
  │
  ▼
Log aggregator (Loki / Elastic / Datadog / Splunk)
  │
  ▼
SIEM rules / dashboards / alerts
```

The control plane nodes run a log-shipping DaemonSet (or a sidecar in the apiserver). It tails the audit log file and ships to the aggregator.

**The audit log is sensitive** (it has request bodies for RequestResponse). The shipping channel should be encrypted (TLS to the aggregator) and authenticated (API keys, mTLS).

## 13. Audit Log Analysis

The standard analysis tools:

* **Elastic / OpenSearch** — full-text search. "Find all failed admission requests for privileged containers in the last 24 hours."
* **Splunk** — similar. SIEM features.
* **Datadog** — log explorer with detection rules.
* **Loki / Grafana** — log aggregation, less powerful search but cheap.

Common queries:

* `responseStatus.code >= 400` — all failed requests.
* `user.username: "alice" AND verb: "delete"` — all deletes by alice.
* `objectRef.resource: "secrets" AND responseStatus.code: 200` — all successful Secret reads.
* `userAgent: "kube-controller-manager" AND responseStatus.code: 200` — controller activity.

Common alerts:

* **Burst of 401s from one IP** — possible brute force.
* **Reads of `kube-system` Secrets by non-system users** — possible escalation.
* **Deletions of nodes or RBAC objects** — possible attack.

## 14. Operations and Debugging

### 14.1 Common commands

```bash
# check the apiserver's audit config
cat /etc/kubernetes/audit-policy.yaml
cat /etc/kubernetes/audit-webhook-config.yaml

# check the apiserver's audit log (on the apiserver's node)
ls -la /var/log/kubernetes/audit/
tail -f /var/log/kubernetes/audit/audit.log
# each line is a JSON event

# count events by response code
grep -o '"code":[0-9]*' /var/log/kubernetes/audit/audit.log | sort | uniq -c

# find all events for a specific user
grep '"username":"alice"' /var/log/kubernetes/audit/audit.log | jq

# find all failed events
jq 'select(.responseStatus.code >= 400)' /var/log/kubernetes/audit/audit.log
```

### 14.2 The "audit log is empty" case

```bash
# 1. Is the audit policy file passed to the apiserver?
kubectl -n kube-system get pod kube-apiserver-<node> -o yaml | grep audit-policy-file

# 2. Is the log path writable?
ls -la /var/log/kubernetes/audit/
# check the apiserver's permissions

# 3. Is the log backend configured?
kubectl -n kube-system get pod kube-apiserver-<node> -o yaml | grep audit-log-path

# 4. Are the rules correct?
# if all rules are level: None, the log is empty by design
```

### 14.3 The "audit log is too big" case

The audit log file is filling disk.

```bash
# 1. Check the volume
du -sh /var/log/kubernetes/audit/

# 2. Check the rotation settings
# audit-log-maxage, audit-log-maxbackup, audit-log-maxsize

# 3. Add None rules for noisy system components
# (see section 11)

# 4. Reduce RequestResponse to Request
# or to Metadata for non-sensitive resources
```

## 15. Gotchas and Common Mistakes

### 15.1 The 25+ common mistakes

1. **The default policy logs everything at Metadata.** This is OK for small clusters, but for production, customize the policy to reduce noise and protect secrets.

2. **The audit policy is read on startup.** Changes to the file require an apiserver restart.

3. **`RequestResponse` logs the request body, including Secrets.** If the audit log is compromised, secrets are exposed. Limit `RequestResponse` to specific resources.

4. **The log backend is on the apiserver's local disk.** If the disk is lost, the audit log is lost. Always ship to an external store.

5. **The webhook backend can drop events.** If the webhook is down, the apiserver's buffer fills and events are dropped. Use the `truncate` parameter to keep the most recent events.

6. **`metadata.managedFields` can be huge.** For server-side-apply-heavy clusters, set `omitManagedFields: true` to reduce volume.

7. **System components generate massive volume.** Without `users: ["system:..."]` filters, the audit log is mostly controller activity.

8. **`kube-system` events should be `None` by default** unless specifically needed.

9. **The audit log has the request URI but not always the response body.** For RequestResponse, both are logged. For Request, only the request.

10. **Audit logs are not encrypted at rest by default.** The log file is on the apiserver's disk. Encrypt the disk or ship to an encrypted store.

11. **The `user.username` for system components is `system:apiserver`, `system:kube-controller-manager`, etc.** Filter them out.

12. **The `user.username` for ServiceAccount is `system:serviceaccount:<ns>:<sa>`.** Use this in rules to filter SA activity.

13. **OIDC group claims are in `user.groups`.** Use `userGroups` in rules.

14. **The `userAgent` is the client.** `kubectl/v1.30.0`, `kubelet/v1.30.0`, `kube-controller-manager`. Useful for filtering.

15. **The `sourceIPs` is the source IP of the request.** Useful for "which IP is this from".

16. **Audit events for failed requests are still emitted.** A 401 (failed authn) or 403 (failed authz) is logged.

17. **The audit log doesn't show what the apiserver did internally** (e.g. leader election, watch events). It shows API requests.

18. **The `objectRef.subresource` is set for subresource requests** (e.g. `pods/exec`, `pods/log`, `deployments/scale`).

19. **The `auditID` is per-request, not per-event.** A long-running watch has one auditID for many events.

20. **A `ResponseStarted` event is emitted for watches** (when the first response is sent). The watch then emits events as data changes, but those are not in the audit log.

21. **The audit log is in JSON, one event per line.** Use `jq` to parse.

22. **The audit log can be 100s of MB per day.** Plan disk and shipping capacity.

23. **The apiserver's log buffer for the webhook backend is limited.** A long webhook outage drops events. The `truncate` parameter keeps the most recent.

24. **A `truncate: true` flag in the webhook config drops the request / response bodies** for events that would otherwise exceed the buffer. Useful for capacity.

25. **The `dynamic` backend (AuditSink CRD) is for k8s 1.28+.** It allows runtime configuration of webhook sinks.

26. **Audit logs are required for compliance.** PCI-DSS, SOC2, HIPAA, FedRAMP all have audit log requirements.

27. **The audit log's `annotations` field is extensible.** Admission controllers, RBAC, etc. can add their own annotations.

28. **A `Panic` event is emitted if the apiserver panics** during the request. This should be alerted on.

29. **The audit log's `level` is set by the matched rule.** If a rule says `Metadata` and the request is denied, the log entry is still `Metadata`. Use this for "no log noise on failed requests" by setting the level to `None` for noisy resources.

30. **The audit log is the apiserver's, not the cluster's.** It only logs API requests. Workload-level activity (file reads, network calls) is not in the audit log. Use Falco for that.

## See also

* [[Kubernetes/concepts/L07-security/10-admission-controllers|Admission Controllers]] — what admission decisions get audited
* [[Kubernetes/concepts/L07-security/03-rbac|RBAC]] — RBAC decisions in the audit log
* [[Kubernetes/concepts/L07-security/20-cluster-hardening|Cluster Hardening]] — enabling audit in the apiserver config
* [[Kubernetes/concepts/L07-security/19-runtime-detection|Runtime Detection]] — workload-level activity (Falco)
