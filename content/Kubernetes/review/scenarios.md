---
title: Scenario-Based Production Incident Reviews
tags: [kubernetes, review, troubleshooting, incidents, scenarios, postmortem]
date: 2026-09-06
description: End-of-level incident review scenarios analyzing stuck rollouts, DNS reachability drops, blocked node drains, and admission webhook outages.
aliases:
  - Kubernetes/review/scenarios
---

# Scenario-Based Production Incident Reviews

Realistic production post-mortems and triage walkthroughs covering multi-layered Kubernetes failure modes.

---

## Scenario 1: Deployment Has 3 Replicas but 0 Available Pods

### Symptom & Alert:
Prometheus triggers `KubeDeploymentReplicasMismatch`:
```
Deployment "checkout-service" has 3 desired replicas, 3 updated replicas, but 0 available replicas.
```

### Step-by-Step Triage:

1. **Inspect Deployment status:**
   ```bash
   kubectl get deployment checkout-service
   ```
   *Output:* `READY 0/3, UP-TO-DATE 3, AVAILABLE 0`

2. **Inspect individual Pod status:**
   ```bash
   kubectl get pods -l app=checkout-service
   ```
   *Output:*
   ```
   NAME                                READY   STATUS    RESTARTS   AGE
   checkout-service-78f898c6d4-5m2ks   0/1     Running   0          4m
   checkout-service-78f898c6d4-8d4np   0/1     Running   0          4m
   checkout-service-78f898c6d4-p9l2s   0/1     Running   0          4m
   ```
   Notice that the Pods are `Running`, but `0/1` containers are `READY`.

3. **Check granular conditions on one Pod:**
   ```bash
   kubectl describe pod checkout-service-78f898c6d4-5m2ks | grep -A 6 "Conditions:"
   ```
   *Output:*
   ```
     Type           Status
     Initialized    True
     Ready          False   <-- NOT READY
     ContainersReady False
     PodScheduled   True
   ```

4. **Inspect events for Readiness Probe failures:**
   ```bash
   kubectl describe pod checkout-service-78f898c6d4-5m2ks | grep -A 5 "Events:"
   ```
   *Output:*
   ```
   Warning  Unhealthy  12s (x8 over 3m)  kubelet  Readiness probe failed: HTTP probe failed with statuscode: 503
   ```

5. **Read application logs:**
   ```bash
   kubectl logs checkout-service-78f898c6d4-5m2ks
   ```
   *Output:* `Database connection pool initialization timed out: postgres-master.db.svc:5432 unreachable`.

### Root Cause:
The application containers booted successfully, but failed their readiness probes because their downstream database dependency was unreachable. Kubelet correctly withheld the `Ready` condition, preventing traffic from reaching unready containers.

### Remediation:
1. Fix the downstream database connectivity.
2. In the deployment manifest, configure `startupProbe` with an appropriate `failureThreshold` to give cold-start initialization ample time before readiness probes begin failing.

---

## Scenario 2: Service Resolves in DNS but TCP Connections Time Out

### Symptom & Alert:
Client microservices report `connection timed out` after 30 seconds when calling `http://inventory.production.svc.cluster.local:8080`.

### Step-by-Step Triage:

1. **Verify DNS resolution from a debug pod:**
   ```bash
   kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup inventory.production.svc.cluster.local
   ```
   *Result:* Resolves successfully to `10.96.45.120`. CoreDNS is healthy.

2. **Verify Service Endpoints:**
   ```bash
   kubectl get endpointslices -l kubernetes.io/service-name=inventory
   ```
   *Result:*
   ```
   NAME              ADDRESSTYPE   PORTS   ENDPOINTS   AGE
   inventory-xk89d   IPv4          8080    <unset>     12m
   ```
   **The Service has ZERO endpoints!**

3. **Compare Service Selector with Pod Labels:**
   ```bash
   # Check service selector
   kubectl get svc inventory -o jsonpath='{.spec.selector}'
   # Output: {"app":"inventory","tier":"backend"}

   # Check actual pod labels
   kubectl get pods -l app=inventory --show-labels
   # Output: app=inventory,tier=api
   ```

### Root Cause:
A label mismatch (`tier: backend` vs `tier: api`). The EndpointSlice controller found 0 pods matching all selector labels. When clients sent SYN packets to the Service VIP, no DNAT rules existed in the node's `nftables` tables, causing packets to be silently dropped.

### Remediation:
Patch the Service's selector to match the actual Pod labels:
```bash
kubectl patch svc inventory -p '{"spec":{"selector":{"tier":"api"}}}'
```
Endpoints appear immediately, and TCP connections succeed.

---

## Scenario 3: HPA Demands 20 Replicas, but Pods Remain Stuck in `Pending`

### Symptom & Alert:
During a flash-sale event, HPA scales up the order-processing deployment from 4 to 20 replicas. However, order processing throughput does not increase, and 16 new pods remain stuck in `Pending`.

### Step-by-Step Triage:

1. **Inspect the pending pods:**
   ```bash
   kubectl get pods -l app=order-processor | grep Pending
   ```

2. **Inspect scheduler events on one pending pod:**
   ```bash
   kubectl describe pod order-processor-65f8d9b4c7-w8s9k | grep -A 5 "Events:"
   ```
   *Output:*
   ```
   Warning  FailedScheduling  45s  default-scheduler  0/6 nodes are available: 6 Insufficient cpu. preemption: 0/6 nodes are available: 6 No preemption victims found for incoming pod.
   ```

3. **Check node allocatable CPU:**
   ```bash
   kubectl describe nodes | grep -A 4 "Allocated resources:"
   ```
   Every worker node has 95% CPU requests committed. The cluster has exhausted its compute capacity.

4. **Check why node autoscaler did not launch new nodes:**
   ```bash
   kubectl describe deployment cluster-autoscaler -n kube-system
   kubectl logs -n kube-system deployment/cluster-autoscaler --tail=50
   ```
   *Output:* `MaxNodesTotal (6) reached, cannot scale out cluster`.

### Root Cause:
The cluster hit the hard capacity ceiling (`maxNodes: 6`) defined in the Cluster Autoscaler configuration. Even though cloud capacity was available, the autoscaler refused to provision additional instances.

### Remediation:
1. Increase the maximum node group limit in the autoscaler configuration.
2. Consider migrating to **Karpenter**, which provisions right-sized compute dynamically without rigid node-group size boundaries.

---

## Scenario 4: `kubectl drain` on a Worker Node Hangs Indefinitely

### Symptom:
During a scheduled cluster node OS upgrade, an engineer executes:
```bash
kubectl drain node-worker-3 --ignore-daemonsets --delete-emptydir-data
```
The command blocks indefinitely, reporting:
```
evicting pod default/payment-gateway-69d8b7-4m8s9
error when evicting pod "payment-gateway-69d8b7-4m8s9": Cannot evict pod as it would violate the pod's disruption budget.
```

### Step-by-Step Triage:

1. **Inspect the PodDisruptionBudget for that workload:**
   ```bash
   kubectl get pdb -A
   ```
   *Output:*
   ```
   NAMESPACE   NAME                  MIN AVAILABLE   ALLOWED DISRUPTIONS   CURRENT
   default     payment-gateway-pdb   2               0                     2
   ```

2. **Check payment-gateway pod replica distribution:**
   ```bash
   kubectl get pods -l app=payment-gateway -o wide
   ```
   *Output:*
   ```
   NAME                                READY   STATUS    NODE
   payment-gateway-69d8b7-4m8s9        1/1     Running   node-worker-3
   payment-gateway-69d8b7-v8k2p        0/1     CrashLoop node-worker-1
   ```

### Root Cause:
The PDB requires `minAvailable: 2`. There are only 2 replicas total, and one replica on `node-worker-1` is crashing (`0/1 Ready`). Therefore, only 1 healthy pod exists. Evicting the pod on `node-worker-3` would drop available pods to 0 (violating the PDB). The Eviction API refuses the eviction request to protect the application.

### Remediation:
1. **Fix the crashing pod first:** Check `kubectl logs payment-gateway-69d8b7-v8k2p --previous` and resolve the crash so that `ALLOWED DISRUPTIONS` becomes 1.
2. Once the second pod is healthy, `kubectl drain` immediately proceeds without downtime.

---

## Scenario 5: Validating Webhook Outage Blocks All Deployments

### Symptom:
Every engineer trying to deploy or update workloads receives an API error:
```
Error from server (InternalError): Internal error occurred: failed calling webhook "validate.security.company.com": 
Post "https://security-validator.security.svc:443/validate?timeout=10s": context deadline exceeded
```

### Step-by-Step Triage:

1. **Identify the failing webhook configuration:**
   ```bash
   kubectl get validatingwebhookconfigurations
   kubectl describe validatingwebhookconfiguration security-validator
   ```

2. **Inspect the failurePolicy on the webhook:**
   ```bash
   kubectl get validatingwebhookconfiguration security-validator -o jsonpath='{.webhooks[*].failurePolicy}'
   ```
   *Output:* `Fail`. The webhook is configured to **fail closed**.

3. **Check the webhook backend pods:**
   ```bash
   kubectl get pods -n security -l app=security-validator
   ```
   *Output:* `security-validator-xxxx-yyyy  0/1  OOMKilled`. The validator pod crashed and is failing to restart.

### Root Cause:
A third-party validating admission webhook was configured with `failurePolicy: Fail`. When the webhook pod crashed, `kube-apiserver` could not evaluate admission requests and refused all resource mutations cluster-wide.

### Emergency Remediation & Architecture Fix:
1. **Emergency unblock:** Temporarily switch the webhook to fail-open while debugging:
   ```bash
   kubectl patch validatingwebhookconfiguration security-validator \
     --type='json' -p='[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]'
   ```
2. **Architecture Prevention:**
   - Migrate simple validation rules from dynamic webhooks to **ValidatingAdmissionPolicy (CEL)**, which evaluates natively inside the API server process with zero network dependencies.
   - For webhooks that must fail-closed, run them with high availability (≥3 replicas, anti-affinity, and a PDB).

---

## Next Steps

Review the foundational curriculum in **[[Kubernetes/concepts/00-hub|Curriculum Hub]]** or practice disaster recovery procedures in **[[Kubernetes/labs/09-gitops-and-lifecycle|Lab 09 — GitOps Delivery & Lifecycle]]**.
