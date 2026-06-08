# Extended Resources and Device Plugins

*"https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/"*

Extended resources are **opaque resources** beyond CPU and memory — GPUs, FPGAs, InfiniBand HCAs, SR-IOV NICs, and custom hardware. They're reported by **device plugins** running on the nodes, scheduled by the standard scheduler (via the `NodeResourcesFit` plugin), and consumed by Pods via the `resources.limits` field.

### Table of Contents

1. [What Extended Resources Solve](#1-what-extended-resources-solve)
2. [The Device Plugin Model](#2-the-device-plugin-model)
3. [Built-in and Common Extended Resources](#3-built-in-and-common-extended-resources)
4. [Reporting Resources: The Node's View](#4-reporting-resources-the-nodes-view)
5. [Consuming Resources: The Pod's View](#5-consuming-resources-the-pods-view)
6. [GPU Scheduling Patterns](#6-gpu-scheduling-patterns)
7. [Time-Slicing and MIG (GPU Sharing)](#7-time-slicing-and-mig-gpu-sharing)
8. [Custom Device Plugins](#8-custom-device-plugins)
9. [ResourceClaim and ResourceClaimTemplate (k8s 1.28+)](#9-resourceclaim-and-resourceclaimtemplate-k8s-128)
10. [Extended Resources and Quotas](#10-extended-resources-and-quotas)
11. [Operations and Debugging](#11-operations-and-debugging)
12. [Gotchas and Common Mistakes](#12-gotchas-and-common-mistakes)

---

## 1. What Extended Resources Solve

Standard k8s resources (CPU, memory, ephemeral-storage) are **not enough** for many workloads:

* **ML / AI** — needs GPUs.
* **HPC** — needs FPGAs, InfiniBand, custom interconnects.
* **Telco / NFV** — needs SR-IOV NICs, DPDK, hardware accelerators.
* **Storage** — needs high-performance local NVMe.

Extended resources let **nodes advertise what they have** (e.g. "I have 4 NVIDIA A100 GPUs"), and **Pods request what they need** (e.g. "give me 1 GPU"). The scheduler places the Pod on a node that has the resource.

```
Node:                Pod:                  Scheduler:
- cpu: 64           - cpu: 4               "Pod wants 1 GPU,
- memory: 256Gi     - memory: 32Gi          only node-2 has 1 free,
- nvidia.com/gpu: 4 - nvidia.com/gpu: 1     schedule there"
```

## 2. The Device Plugin Model

A **device plugin** is a **gRPC daemon** that runs on the node (as a DaemonSet, usually) and registers the resources with the kubelet.

```
Node
├── kubelet
│     │
│     └── gRPC (ListAndWatch)
│              ▲
│              │
│     ┌────────┴────────┐
│     │ device plugin   │
│     │ (DaemonSet)     │
│     │                 │
│     │ NVIDIA GPU      │
│     │ Operator        │
└─────────────────────┘
```

The flow:

1. The device plugin starts on the node.
2. It registers itself with the kubelet via the Registration gRPC API.
3. The kubelet calls `ListAndWatch` to get the available devices.
4. The kubelet exposes the resources to the apiserver via the Node's `status.allocatable` and `status.capacity`.
5. The scheduler sees the resources and can place Pods.
6. When a Pod uses a resource, the device plugin's `Allocate` gRPC method is called, which prepares the device for the container (e.g. sets up CUDA libraries, mounts devices).
7. The kubelet mounts the device into the container.

The device plugin API is a **stable gRPC interface** defined in `k8s.io/kubelet/pkg/apis/deviceplugin/v1beta1/`. Vendors write plugins in any language that supports gRPC (Go is most common).

### 2.1 The registration handshake

```go
// pseudo-Go
func (m *MyDevicePlugin) Register() error {
    conn, err := grpc.Dial(
        filepath.Join(devicePluginPath, "kubelet.sock"),
        grpc.WithInsecure(),
    )
    defer conn.Close()
    client := pluginapi.NewRegistrationClient(conn)
    
    req := &pluginapi.RegisterRequest{
        Version:      pluginapi.Version,
        Endpoint:     "my-device-plugin.sock",
        ResourceName: "example.com/foo",
        Options:      &pluginapi.DevicePluginOptions{},
    }
    _, err = client.Register(ctx, req)
    return err
}
```

The plugin creates a Unix socket, the kubelet calls `Register`, then `ListAndWatch` for the device list.

## 3. Built-in and Common Extended Resources

### 3.1 CPU and memory

Standard, not extended. The kubelet reports them automatically.

### 3.2 NVIDIA GPUs

The **NVIDIA Device Plugin** for Kubernetes. DaemonSet that detects NVIDIA GPUs and registers them as `nvidia.com/gpu`.

```yaml
# node status
status:
  allocatable:
    nvidia.com/gpu: 4
  capacity:
    nvidia.com/gpu: 4
```

The plugin also:

* Sets up the NVIDIA container runtime.
* Mounts CUDA libraries.
* Configures the GPU for the container.

### 3.3 Other accelerators

| Resource | Vendor / Project | Common use |
|---|---|---|
| `nvidia.com/gpu` | NVIDIA | ML, AI, CUDA workloads |
| `amd.com/gpu` | AMD | ML on AMD GPUs (ROCm) |
| `intel.com/gpu` | Intel | Integrated GPU, Intel Xe |
| `nvidia.com/mig-1g.5gb` | NVIDIA MIG | Multi-Instance GPU partitioning |
| `nvidia.com/gpu.shared` | Time-slicing | Multiple Pods sharing one GPU |
| `hugepages-1Gi` | (built-in) | Huge page allocation |
| `example.com/infiniband` | Custom | InfiniBand HCA |
| `example.com/fpga` | Intel / Xilinx | FPGA workloads |

### 3.4 Huge pages

Huge pages are a **built-in extended resource**, but they work differently from plugin-reported resources. They're declared at the kubelet level (per node) and reported as `hugepages-2Mi` or `hugepages-1Gi`.

```yaml
# kubelet flag
--hugepages-1Gi=4

# Pod
resources:
  requests:
    hugepages-1Gi: 2Gi
  limits:
    hugepages-1Gi: 2Gi
```

The Pod's container is allocated 2 huge pages (2 GiB of huge pages).

## 4. Reporting Resources: The Node's View

The kubelet reports the node's resources in `status.allocatable` and `status.capacity`:

```yaml
apiVersion: v1
kind: Node
metadata:
  name: gpu-node-1
status:
  capacity:
    cpu: "64"
    memory: 256Gi
    nvidia.com/gpu: 4
    hugepages-1Gi: 4Gi
  allocatable:
    cpu: 63500m               # 63.5 cores (500m reserved)
    memory: 250Gi             # 250 GB (6 GB reserved)
    nvidia.com/gpu: 4
    hugepages-1Gi: 4Gi
```

`allocatable` is what the scheduler sees. `capacity` is the physical total.

### 4.1 Manually advertising resources

For some resources (mostly for testing), you can manually advertise them:

```bash
# if you have a custom resource that's not detected by a device plugin
curl -k -X POST https://<kubelet>:<port>/api/v1/nodes/<name>/capacity
```

Or via the kubelet flag:

```bash
# not a real flag, but you can patch the Node object
kubectl patch node <name> -p '{"status":{"capacity":{"example.com/foo":"2"}}}'
```

**Manually advertised resources are not consumed by Pods** — the kubelet doesn't know how to actually give them to containers. Use a device plugin for real resources.

## 5. Consuming Resources: The Pod's View

A Pod requests an extended resource via `resources.requests` and `resources.limits`:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: ml-trainer }
spec:
  containers:
  - name: trainer
    image: tensorflow/tensorflow:latest-gpu
    resources:
      requests:
        nvidia.com/gpu: 1
      limits:
        nvidia.com/gpu: 1
```

For most extended resources, `requests` and `limits` are the **same value** — the resource is not compressible. You can't ask for "0.5 GPUs".

### 5.1 The scheduler's view

The scheduler's `NodeResourcesFit` plugin filters out nodes that don't have the resource. For a Pod asking for `nvidia.com/gpu: 1`:

- A node with `nvidia.com/gpu: 0` is dropped.
- A node with `nvidia.com/gpu: 1` is considered (and 1 is reserved).
- A node with `nvidia.com/gpu: 4` is considered (and 1 is reserved; 3 remain).

### 5.2 The kubelet's allocation

When the Pod is scheduled, the kubelet:

1. Calls the device plugin's `Allocate` gRPC method.
2. The plugin returns the device IDs, environment variables, mount paths, etc.
3. The kubelet sets up the container with the allocated devices.

For NVIDIA GPUs, this is:

* Mount the GPU device files (`/dev/nvidia0`).
* Set environment variables (`NVIDIA_VISIBLE_DEVICES=0`).
* Mount the NVIDIA libraries.
* Configure the container runtime for GPU access.

## 6. GPU Scheduling Patterns

### 6.1 One GPU per Pod (most common)

```yaml
spec:
  containers:
  - name: trainer
    resources:
      limits:
        nvidia.com/gpu: 1
```

One Pod, one GPU. The Pod owns the GPU exclusively.

### 6.2 Multiple GPUs per Pod

```yaml
spec:
  containers:
  - name: trainer
    resources:
      limits:
        nvidia.com/gpu: 4
```

For distributed training (e.g. 4 GPUs for one model). The Pod owns 4 GPUs.

### 6.3 GPU type selection

```yaml
spec:
  nodeSelector:
    nvidia.com/gpu.product: NVIDIA-A100-SXM4-80GB
  containers:
  - name: trainer
    resources:
      limits:
        nvidia.com/gpu: 1
```

The Pod is scheduled only on nodes with A100 80GB GPUs. **The GPU model is a node label** — the device plugin or a custom controller sets it.

### 6.4 GPU taints for dedicated nodes

```bash
# taint GPU nodes so only GPU Pods land there
kubectl taint nodes gpu-node-1 nvidia.com/gpu=present:NoSchedule
```

```yaml
# GPU Pod tolerates the taint
spec:
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
  containers:
  - name: trainer
    resources:
      limits:
        nvidia.com/gpu: 1
```

This is a common pattern for mixed clusters (CPU + GPU nodes).

## 7. Time-Slicing and MIG (GPU Sharing)

GPUs are expensive. Time-slicing and MIG let multiple Pods share a single GPU.

### 7.1 Time-slicing

The NVIDIA device plugin's time-slicing config lets multiple Pods use the same GPU in **time slices** (rapid context-switching). Each Pod sees the GPU, but they share the compute.

```yaml
# ConfigMap for the NVIDIA device plugin
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicingConfig:
        resources:
        - name: nvidia.com/gpu
          replicas: 4       # 4 Pods can share 1 GPU
```

The plugin advertises `nvidia.com/gpu: 4` per physical GPU. A Pod asking for `nvidia.com/gpu: 1` gets a time slice.

**Time-slicing is not isolation.** Two Pods on the same GPU still share the GPU's memory and compute. They're rapidly swapped. For workloads that don't fully use the GPU (inference, light training), this works. For heavy compute (large model training), it doesn't.

### 7.2 MIG (Multi-Instance GPU)

A100, H100 GPUs support **hardware partitioning** into multiple isolated instances. Each MIG instance has its own memory, compute, and decoders. True hardware isolation.

```yaml
# nvidia device plugin config for MIG
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin
data:
  config.yaml: |
    version: v1
    migStrategies:
      nvidia.com/gpu: "mixed"   # advertise MIG instances as separate resources
```

The plugin advertises `nvidia.com/mig-1g.5gb` (1 instance with 5 GB) etc. A Pod asks for a specific MIG instance.

```yaml
spec:
  containers:
  - name: inference
    resources:
      limits:
        nvidia.com/mig-1g.5gb: 1
```

**MIG is true isolation** — each instance has its own memory and compute. Two Pods on MIG instances don't interfere.

### 7.3 CUDA MPS

CUDA Multi-Process Service allows multiple processes to share a GPU more efficiently. Less common in k8s.

## 8. Custom Device Plugins

For custom hardware, you write a device plugin. The minimum is:

1. A gRPC server implementing the `Registration` and `ListAndWatch` APIs.
2. A way to allocate the device (the `Allocate` API).
3. Deployment as a DaemonSet (one Pod per node).

The reference implementation is in `k8s.io/dynamic-resource-allocation` and the example plugin in the k8s source tree.

### 8.1 The allocation response

```go
// what Allocate returns
type ContainerAllocateResponse struct {
    Envs          map[string]string  // environment variables
    Mounts        []*Mount           // files to mount
    Devices       []*DeviceSpec      // device files
    Annotations   map[string]string
    CDIDevices    []*CDIDevice       // CDI devices
}
```

The kubelet applies these to the container. The plugin can set env vars, mount files, and expose devices.

### 8.2 Resource granularity

The plugin reports a `resourceName` (e.g. `example.com/foo`) and a count. The granularity is up to the plugin:

* A plugin that reports `example.com/foo: 1` means "1 unit of foo".
* A plugin that reports `example.com/foo: 8` means "8 units of foo".

The Pod's request must be a positive integer. The kubelet doesn't know about partial units.

## 9. ResourceClaim and ResourceClaimTemplate (k8s 1.28+)

The **Dynamic Resource Allocation (DRA)** feature (alpha in 1.28, beta in 1.30) extends extended resources with first-class allocation objects.

### 9.1 ResourceClaim

```yaml
apiVersion: resource.k8s.io/v1alpha1
kind: ResourceClaim
metadata: { name: ml-claim }
spec:
  resourceClassName: gpu-a100
  allocationMode: WaitForFirstConsumer
```

A `ResourceClaim` is a request for a resource. The scheduler matches it to an available device. The Pod references the claim by name.

### 9.2 The Pod view

```yaml
spec:
  containers:
  - name: trainer
    resources:
      claims:
      - name: ml-claim
```

The Pod asks for the claim. The scheduler allocates the claim to a device on a node, and the kubelet exposes the device to the container.

### 9.3 ResourceClaimTemplate (for StatefulSets)

```yaml
apiVersion: resource.k8s.io/v1alpha1
kind: ResourceClaimTemplate
metadata: { name: gpu-claim }
spec:
  metadata: { name: gpu-claim }
  spec:
    resourceClassName: gpu-a100
```

A StatefulSet uses `ResourceClaimTemplate` to create one claim per replica. Each Pod gets its own GPU.

### 9.4 Why this exists

DRA is the **next generation** of extended resources:

* **Structured claims** (not just opaque integers).
* **First-class scheduler support** (the scheduler has a plugin for DRA).
* **Class-based selection** (multiple classes of GPU, with priorities).
* **Init-time allocation** (allocate when the Pod starts, not before).

DRA is still in alpha/beta as of 1.30. Adoption is early. The device plugin model is still the standard.

## 10. Extended Resources and Quotas

ResourceQuota supports extended resources:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-quota
  namespace: ml
spec:
  hard:
    requests.nvidia.com/gpu: "8"
    limits.nvidia.com/gpu: "8"
```

The namespace can have at most 8 GPUs requested across all Pods. The sum of Pods' `requests.nvidia.com/gpu` must not exceed 8.

**`requests` and `limits` are separate quotas.** A Pod that requests 4 GPUs and limits 4 GPUs counts as 4 against each. A Pod that requests 1 and limits 4 counts as 1 against `requests` and 4 against `limits`.

## 11. Operations and Debugging

### 11.1 Common commands

```bash
# check a node's resources
kubectl describe node <name>
# look at "Allocated resources" and "Capacity"

# check Pod's resource requests
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].resources}'

# check the device plugin
kubectl -n kube-system get pods -l app=nvidia-device-plugin
kubectl -n kube-system logs -l app=nvidia-device-plugin --tail=100

# check the kubelet's view
# (on the node)
ls /var/lib/kubelet/plugins/    # registered plugins
ls /var/lib/kubelet/plugins_registry/   # plugin sockets
```

### 11.2 The "GPU not allocated" checklist

```bash
# 1. Does the node have the resource?
kubectl describe node <gpu-node> | grep nvidia

# 2. Is the device plugin running?
kubectl -n kube-system get pods -l app=nvidia-device-plugin
# the Pod should be Running on the GPU node

# 3. Is the Pod requesting the right resource?
kubectl get pod <pod> -o yaml
# look for resources.limits."nvidia.com/gpu"

# 4. Is the device plugin registered with the kubelet?
# (on the node)
ls /var/lib/kubelet/plugins_registry/
# look for nvidia-gpu.sock

# 5. Check the kubelet logs
journalctl -u kubelet --since "5 minutes ago" | grep -i gpu
```

### 11.3 The "GPU allocated but not visible to container" case

The Pod has `nvidia.com/gpu: 1`, the node has 4 GPUs, the Pod is running, but `nvidia-smi` inside the container shows no GPU.

```bash
# 1. Is the device plugin's Allocate response correct?
# check the device plugin logs
kubectl -n kube-system logs -l app=nvidia-device-plugin

# 2. Is the NVIDIA runtime configured?
# check the container runtime config
# (Docker: /etc/docker/daemon.json; containerd: /etc/containerd/config.toml)

# 3. Is the NVIDIA driver loaded on the node?
nvidia-smi    # on the node
# should show the GPUs

# 4. Is the container image CUDA-enabled?
# some images don't have CUDA libraries
```

## 12. Gotchas and Common Mistakes

### 12.1 The 20+ common mistakes

1. **Extended resources are integer-only.** You can't ask for "0.5 GPUs". Either 1 or 0.

2. **A device plugin must run on every node that has the resource.** If a node has 4 GPUs but no device plugin, the kubelet reports `nvidia.com/gpu: 0`. The scheduler can't place GPU Pods there.

3. **The device plugin must register with the kubelet** before the kubelet reports the resource. A buggy plugin = a node with no resources.

4. **`requests` and `limits` for extended resources should usually be equal.** Unlike CPU/memory, you can't "burst" past the request.

5. **Time-slicing is not isolation.** Two Pods on the same time-sliced GPU still share the GPU's memory. For ML training, this can cause OOM.

6. **MIG requires MIG-enabled GPUs (A100, H100).** Older GPUs don't support MIG.

7. **The device plugin's `Allocate` is a hot path.** If the plugin is slow, Pod startup is slow.

8. **Custom resources (`example.com/foo`) are opaque to the scheduler.** The scheduler can't tell what they are. It just counts them.

9. **A `ResourceQuota` with extended resources blocks Pods at admission.** If the namespace is at quota, the Pod is rejected with "exceeded quota".

10. **Device plugin updates restart containers.** A plugin version bump can cause Pod evictions.

11. **The kubelet's `--feature-gates=DynamicResourceAllocation=true`** must be set for DRA. Older kubelets don't support it.

12. **DRA's `ResourceClaim` is in alpha/beta.** Don't depend on it for production until 1.32+ (likely GA).

13. **GPU Pods need the NVIDIA runtime.** Without it, the container can't access the GPU even if `nvidia.com/gpu` is allocated.

14. **GPU taints need to be tolerated.** A taint on a GPU node prevents non-GPU Pods from being scheduled there. **This is correct**, but easy to forget.

15. **A Pod with `nvidia.com/gpu: 1` doesn't reserve the GPU's memory.** Time-sliced sharing can cause memory exhaustion. Use MIG or check memory usage.

16. **The kubelet reports `allocatable` differently from `capacity`.** System reserved (kubelet, kernel) is subtracted. A 4-GPU node might have `allocatable.nvidia.com/gpu: 3`.

17. **A node without the device plugin can still be scheduled for GPU Pods** if the device plugin is misconfigured. The Pod is scheduled, the kubelet tries to allocate, fails. The Pod stays Pending.

18. **Huge pages are a separate resource.** They're not allocated by a device plugin; they're declared at the kubelet level. A node with 4 huge pages can have 4 Pods each asking for 1, or 2 Pods each asking for 2.

19. **The kubelet's `--max-pods` flag limits Pod count, not resource count.** A node with 4 GPUs can still have many Pods (each with 0.1 GPUs, in time-sliced mode).

20. **GPU sharing with cgroup v1 is broken.** Use cgroup v2 for time-slicing and MIG.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]] — the broader scheduling context
* [[Kubernetes/concepts/L06-scheduling-scaling/12-scheduler-internals|Scheduler Internals]] — the NodeResourcesFit plugin
* [[Kubernetes/concepts/L05-config-storage/08-resource-quota|ResourceQuota]] — namespace-level extended resource quotas
