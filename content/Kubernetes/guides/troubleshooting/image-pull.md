---
title: ImagePullBackOff / ErrImagePull
tags:
  - Kubernetes
  - Troubleshooting
  - Images
  - Registry
---

The kubelet can't pull the container image. The pod sits in `ImagePullBackOff` (or `ErrImagePull` for the very first attempt) and the kubelet backs off retries. This is **registry or credentials**, not the application.

## Symptoms

```bash
$ kubectl get pods
NAME    READY   STATUS             RESTARTS   AGE
web-1   0/1     ImagePullBackOff   0          5m
api-2   0/1     ErrImagePull       0          30s
worker  0/1     ImagePullBackOff   0          8m
```

`RESTARTS = 0` — the container has never started. Compare to CrashLoopBackOff (container started and crashed) or Pending (pod never got scheduled).

The status transitions are:

```
ErrImagePull  →  (retry)  →  ErrImagePull  →  (backoff)  →  ImagePullBackOff
```

`ErrImagePull` is the immediate failure. `ImagePullBackOff` means the kubelet has given up retrying for now and will try again later.

## The 30-second diagnosis

```bash
# 1. describe — events will tell you why
kubectl describe pod web-1 | tail -30

# 2. which image is it trying to pull?
kubectl get pod web-1 -o jsonpath='{.spec.containers[*].image}'

# 3. try the pull manually from inside the cluster
kubectl run debug --rm -it --image=busybox --restart=Never -- \
  wget -qO- https://my-registry.example.com/v2/

# 4. check the imagePullSecrets
kubectl get pod web-1 -o jsonpath='{.spec.imagePullSecrets}'
```

## The taxonomy of causes

```
┌──────────────────────────────────────────────────────────────┐
│                  ImagePullBackOff                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Image name typo            (myorg/web vs myorg/wed)      │
│  2. Image tag doesn't exist    (v2 vs v2.0.0-rc1)            │
│  3. Private registry auth      (no imagePullSecrets)         │
│  4. Wrong registry endpoint    (typo in image prefix)        │
│  5. Network can't reach        (proxy, NAT, EgressPolicy)    │
│  6. Architecture mismatch      (arm64 vs amd64)               │
│  7. Registry rate-limited      (Docker Hub, GHCR limits)     │
│  8. Image too large            (registry timeout, OOM in pull)│
│  9. Storage limit              (no room to extract layers)   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 1. Image name typo

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -10
Events:
  Warning  Failed     5m   kubelet  Failed to pull image "myorg/wed:v2":
    failed to pull and unpack image "docker.io/myorg/wed:v2":
    failed to resolve reference "docker.io/myorg/wed:v2":
    pull access denied, repository does not exist or may require authorization
```

The image name is wrong. `myorg/wed` doesn't exist; you meant `myorg/web`.

**Diagnosis:**

```bash
# 1. confirm the image exists in the registry
docker manifest inspect myorg/web:v2
# or
curl -s https://my-registry/v2/myorg/web/manifests/v2 | jq .

# 2. is the typo in the deployment or the pod?
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Fix:** correct the image name. `kubectl set image` is the right tool:

```bash
kubectl set image deployment/web web=myorg/web:v2
```

## 2. Image tag doesn't exist

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -10
Events:
  Warning  Failed     5m   kubelet  Failed to pull image "myorg/web:v2.0.0-rc1":
    [errno 2] could not find reference "v2.0.0-rc1" in repository "myorg/web"
```

The repository exists; the tag doesn't.

**Diagnosis:**

```bash
# 1. list tags in the registry
crane ls myorg/web

# 2. check what you tried
docker manifest inspect myorg/web:v2.0.0-rc1

# 3. (Docker Hub)
# https://hub.docker.com/v2/repositories/myorg/web/tags/?page_size=100
```

**Common sub-causes:**

1. **Pushed wrong tag.** You built `myorg/web:v2` but the deployment says `:v2.0.0-rc1`. The tag never existed.
2. **Tag was deleted.** Registry policies can delete tags. Garbage collection on Docker Hub, lifecycle policies on ECR.
3. **Multi-arch manifest doesn't include your platform.** The image exists, but only has arm64 manifests, and you're on amd64.
   ```bash
   $ docker manifest inspect myorg/web:v2
   {
     "mediaType": "application/vnd.docker.distribution.manifest.list.v2+json",
     "manifests": [
       {"platform": {"architecture": "arm64", "os": "linux"}}
     ]
   }
   ```
   Fix: build with `--platform linux/amd64,linux/arm64`.

## 3. Private registry auth

The image is in a private registry, the kubelet needs creds, and there are no `imagePullSecrets` (or the wrong ones).

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -10
Events:
  Warning  Failed     5m   kubelet  Failed to pull image "registry.example.com/myorg/web:v2":
    Error response from daemon: pull access denied for registry.example.com/myorg/web,
    repository does not exist or may require 'docker login'
```

**Diagnosis:**

```bash
# 1. does the pod have imagePullSecrets?
kubectl get pod web-1 -o jsonpath='{.spec.imagePullSecrets}' | jq .
# []   <-- no secrets = no auth

# 2. does the deployment have imagePullSecrets?
kubectl get deploy web -o jsonpath='{.spec.template.spec.imagePullSecrets}' | jq .

# 3. does the service account have the right secrets?
kubectl get sa default -o jsonpath='{.imagePullSecrets}' | jq .
# serviceaccount "default" in "my-ns":
# []
# no secrets here either
```

**Fix — three approaches:**

**Approach 1: Pod-level imagePullSecrets** (most explicit):

```bash
# 1. create the docker-registry secret
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=alice \
  --docker-password=xxx \
  --docker-email=alice@example.com \
  -n my-ns

# 2. add to the pod spec
kubectl patch deploy web -p '{
  "spec": {
    "template": {
      "spec": {
        "imagePullSecrets": [{"name": "regcred"}]
      }
    }
  }
}'
```

**Approach 2: ServiceAccount-level** (cleaner for namespaces):

```bash
# 1. add the secret to the SA
kubectl patch sa default -p '{
  "imagePullSecrets": [{"name": "regcred"}]
}' -n my-ns

# 2. all pods in the namespace using "default" SA now have the secret
```

**Approach 3: Node-level** (for kubelet to use across all pods on the node):

```bash
# on each node, configure the containerd/CRI-O registry credentials
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".registry.configs."registry.example.com".auth]
  username = "alice"
  password = "xxx"
```

**Common gotchas:**

* **Secret is in the wrong namespace.** `imagePullSecrets` is namespaced. A secret in `kube-system` doesn't help a pod in `my-ns`.
* **Secret was deleted.** Someone ran `kubectl delete secret regcred`. Pods that were already running keep their images cached; new pods fail to pull.
* **The registry requires a different auth method.** AWS ECR uses temporary tokens (refreshed every 12h). Azure ACR uses different formats. GCR uses JSON keys or workload identity.
* **The secret was created from a working `~/.docker/config.json` but the JSON has `auths` at the wrong level** (k8s expects `auths.<server>.auth` and `auths.<server>.username`).
* **Using `kubernetes.io/dockerconfigjson` but the secret has the wrong type.**
  ```bash
  kubectl get secret regcred -o jsonpath='{.type}'
  # should be: kubernetes.io/dockerconfigjson
  # if it's Opaque, the kubelet ignores it
  ```
  Re-create with `kubectl create secret docker-registry` (which sets the right type).

## 4. Wrong registry endpoint

The image has a registry prefix that resolves to the wrong place. Common cases:

| Image | Resolves to |
|-------|-------------|
| `nginx` | `docker.io/library/nginx` |
| `myorg/web` | `docker.io/myorg/web` |
| `registry.example.com/myorg/web` | `registry.example.com/myorg/web` |
| `gcr.io/myproj/web` | `gcr.io/myproj/web` |
| `1234.dkr.ecr.us-east-1.amazonaws.com/web` | ECR registry |
| `quay.io/myorg/web` | `quay.io/myorg/web` |

**Signatures:**

```bash
# if you used a private registry but omitted the prefix
$ kubectl describe pod web-1
Failed to pull image "myorg/web:v2":
  pull access denied, repository does not exist or may require authorization
# because Docker Hub has no "myorg/web" (you meant your private registry)
```

**Fix:** include the registry prefix in the image name.

## 5. Network can't reach the registry

DNS works in the cluster, but the registry is unreachable.

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -10
Events:
  Warning  Failed     5m   kubelet  Failed to pull image "registry.example.com/myorg/web:v2":
    failed to do request: Head "https://registry.example.com/v2/myorg/web/manifests/v2":
    dial tcp: lookup registry.example.com on 10.96.0.10:53: no such host
```

```bash
Warning  Failed     5m   kubelet  Failed to pull image "registry.example.com/myorg/web:v2":
  dial tcp 10.0.0.5:443: i/o timeout
```

**Diagnosis:**

```bash
# 1. can the cluster resolve the registry's DNS?
kubectl run debug --rm -it --image=busybox --restart=Never -- \
  nslookup registry.example.com

# 2. can it reach the registry?
kubectl run debug --rm -it --image=busybox --restart=Never -- \
  wget -qO- https://registry.example.com/v2/ ; echo

# 3. from the node
ssh node-1
$ curl -sS https://registry.example.com/v2/ ; echo
$ nslookup registry.example.com
```

**Common sub-causes:**

1. **DNS not configured for the registry's domain.** Especially for private registries on internal domains.
   Fix: add a `dnsConfig` or use `hostAliases` on the pod.

2. **HTTP proxy required.** The cluster is behind a corporate proxy, and the kubelet isn't using it.
   Fix: configure the kubelet's `--http-proxy` flag, or set `HTTPS_PROXY` in the containerd/CRI-O config.

3. **NetworkPolicy blocks egress to the registry.** Default-deny NetworkPolicy without an egress allow.
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   spec:
     podSelector: {}
     policyTypes: [Egress, Ingress]
     # no egress rules = no egress allowed
   ```
   Fix: add an egress rule for the registry.

4. **Registry is on a private network the cluster can't reach.** Common with on-prem or hybrid setups.
   Fix: VPC peering, VPN, or proxy.

5. **TLS cert issue.** Registry uses a private CA, and the kubelet doesn't trust it.
   ```bash
   $ kubectl describe pod web-1 | tail -5
   x509: certificate signed by unknown authority
   ```
   Fix: add the CA cert to the node's trust store, or configure the containerd registry config with `tls_config`.

## 6. Architecture mismatch

The image was built for a different CPU architecture than the node.

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -5
Events:
  Warning  Failed     5m   kubelet  Failed to pull image "myorg/web:v2":
    no matching manifest for linux/amd64 in the manifest list entries
```

The image only has `linux/arm64` (built on M1 Mac) and the node is `linux/amd64`.

**Diagnosis:**

```bash
# 1. node architecture
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.architecture}'
# amd64

# 2. image architectures
docker manifest inspect myorg/web:v2
# or
crane manifest myorg/web:v2 | jq '.manifests[].platform'
```

**Fix:**

```bash
# rebuild for the target platform
docker buildx build --platform linux/amd64 -t myorg/web:v2 .

# or build for both
docker buildx build --platform linux/amd64,linux/arm64 -t myorg/web:v2 --push .
```

## 7. Registry rate-limited

Docker Hub: 100 pulls / 6 hours for anonymous, 200 for authenticated (free tier).
GHCR: 5000 / hour with auth.

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -5
Events:
  Warning  Failed     5m   kubelet  Failed to pull image "library/nginx:latest":
    toomanyrequests: You have reached your pull rate limit
```

**Common in clusters pulling from Docker Hub directly.**

**Fix:**

1. **Mirror to Docker Hub authenticated users** — `docker login` once on each node.
2. **Use a registry mirror** — configure containerd/CRI-O to pull from a mirror (e.g., `mirror.gcr.io` for Docker Hub).
3. **Cache locally** — run a Harbor / ECR / GCR mirror in your own infrastructure, pull from there.
4. **Pre-pull images** — use a DaemonSet or `node-image` to pre-populate node caches.

## 8. Image too large

The image is hundreds of MB or GB. Pulling it takes longer than the kubelet's pull timeout (default 1 minute for the manifest, longer for the actual pull).

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -5
Events:
  Warning  Failed     8m   kubelet  Failed to pull image "myorg/web:v2":
    rpc error: code = Unknown desc = context deadline exceeded
```

**Diagnosis:**

```bash
# 1. image size
docker inspect myorg/web:v2 --format='{{.Size}}'   # bytes

# 2. is the image multi-GB?
# 1.2 GB, mostly from a fat base image (ubuntu + node + npm install)
```

**Fix:** use smaller base images:

```dockerfile
# bad: 1.2 GB
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y nodejs npm
COPY . .
RUN npm install
CMD ["node", "server.js"]

# better: 200 MB
FROM node:20-slim
COPY package*.json ./
RUN npm ci --only=production
COPY . .
CMD ["node", "server.js"]

# best: 80 MB
FROM node:20-alpine
COPY package*.json ./
RUN npm ci --only=production
COPY . .
CMD ["node", "server.js"]

# or even smaller with multi-stage builds
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY package*.json ./
RUN npm ci --only=production
CMD ["node", "dist/server.js"]
```

## 9. Storage limit (no room to extract)

The node's ephemeral storage is full, and the kubelet can't extract the image layers.

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -5
Events:
  Warning  Failed     5m   kubelet  Failed to pull image "myorg/web:v2":
    failed to extract layer sha256:...
    write /var/lib/containerd/.../layer.tar: no space left on device
```

```bash
$ kubectl describe node node-1 | grep -A 3 "Conditions:"
Conditions:
  Type             Status  Reason
  DiskPressure     True   LowDisk
```

**Diagnosis:**

```bash
# 1. node disk
kubectl describe node node-1 | grep -E "DiskPressure|ephemeral-storage"

# 2. on the node
ssh node-1
$ df -h /var/lib/containerd /var/lib/kubelet
$ du -sh /var/lib/containerd /var/lib/kubelet
```

**Fix:** clean up old images, expand disk, or change image storage location.

## The "is it the registry or the cluster?" test

```bash
# 1. can *you* pull the image from outside the cluster?
docker pull myorg/web:v2

# 2. can a *pod* in the cluster pull any image?
kubectl run debug --rm -it --image=busybox --restart=Never -- echo "pulled busybox"
# if THIS fails, it's a network / kubelet / registry config issue
# if THIS works but the real image fails, it's specific to that image/credentials
```

## The "is it the secret?" test

```bash
# decode a dockerconfigjson secret
kubectl get secret regcred -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
```

You should see:

```json
{
  "auths": {
    "registry.example.com": {
      "username": "alice",
      "password": "xxx",
      "email": "alice@example.com",
      "auth": "YWxpY2U6eHh4"
    }
  }
}
```

If the server is wrong, the username is wrong, or the auth doesn't base64-decode to `username:password`, the secret is the problem.

## Pulling from a private registry the kubelet doesn't know about

Some managed services (ECR, ACR, GCR) auto-provision credentials via workload identity. If you have that set up, **don't** create a `docker-registry` secret — the kubelet handles auth automatically via the cloud's metadata service.

```bash
# EKS with IRSA — pods use the node's IAM role, no imagePullSecrets needed
# GKE with Workload Identity — same idea
# AKS with Managed Identity — same
```

If you have a working cloud-native setup but you've also created an `imagePullSecrets`, the kubelet will use the secrets first, and may fail if those secrets are stale or wrong.

## Pulling through a proxy

```bash
# kubelet config
--proxy-url=https://proxy.example.com:3128
--no-proxy=localhost,127.0.0.1,.svc,.cluster.local
```

And for containerd:

```toml
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri"]
  [plugins."io.containerd.grpc.v1.cri".registry]
    [plugins."io.containerd.grpc.v1.cri".registry.configs]
      [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.example.com"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.example.com".tls]
          ca_file = "/etc/ssl/certs/registry-ca.pem"
```

## Common gotchas

* **`ImagePullBackOff` is normal for typos** — the kubelet will keep retrying for a long time. If you've fixed the issue, `kubectl delete pod <name>` to force an immediate re-pull.
* **The "latest" tag is a liar.** `image: myorg/web:latest` doesn't mean "the newest stable version" — it means "whatever was tagged as `latest` at pull time." Use specific tags (e.g., `v2.1.4` or a SHA digest `myorg/web@sha256:abc123...`).
* **Multi-arch images need a manifest list.** If you only built for one platform, the image won't pull on the other.
* **The default service account has no imagePullSecrets by default.** You have to add them.
* **Don't put credentials in your image name.** `image: myorg/web:v2?token=xxx` doesn't work; the kubelet doesn't parse query strings. Use `imagePullSecrets`.
* **Pull policies** — `imagePullPolicy: IfNotPresent` (default) skips pull if image is cached. `Always` re-pulls every time. `Never` never pulls (assumes cached).
  ```yaml
  containers:
  - name: web
    image: myorg/web:v2
    imagePullPolicy: Always   # useful for `:latest` to ensure freshness
  ```
* **Cached images don't get cleaned up automatically.** Nodes accumulate old images. Use a tool like `image-gc` or `crictl rmi` to clean.
* **Pulling from one registry, pushing to another.** Multi-cluster setups often have a local mirror. Make sure image references match the local mirror's path, not the source registry's.
* **Pod sandbox image.** Even if your container image pulls fine, the pod needs a sandbox image (e.g., `registry.k8s.io/pause:3.9`). If the sandbox image is blocked, the pod fails to start.
* **A failed `imagePullBackOff` is a "kicked off but eventually failed" — the kubelet might keep retrying for hours.** If you don't see an event for a while, that's the backoff. Force a re-pull with `kubectl delete pod`.

## See also

* [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] — when the image is fine, the app crashes
* [[Kubernetes/guides/troubleshooting/pod-pending|pod-pending]] — when the pod can't even start scheduling
* [[Kubernetes/guides/tools/kubectl|kubectl]] — the CLI
* [[Kubernetes/concepts/L05-config-storage/02-secrets|secrets]] — imagePullSecrets are secrets
