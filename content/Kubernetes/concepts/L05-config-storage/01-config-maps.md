# ConfigMaps

*"https://kubernetes.io/docs/concepts/configuration/configmap/"*

A ConfigMap is a **key-value store for configuration data** that you can inject into containers as environment variables, files in a volume, or command-line arguments. It's the standard way to separate configuration from container images.

## The problem ConfigMaps solve

Your container image has the application code. The configuration (database URL, feature flags, environment-specific settings) varies between dev, staging, production. ConfigMaps let you change configuration without rebuilding the image.

```
No ConfigMap:        image = nginx:1.27 + hardcoded config baked in
                     → new image for every environment

With ConfigMap:      image = nginx:1.27
                     ConfigMap = environment-specific config
                     → same image, different config
```

## Creating a ConfigMap

### From literal values

```bash
kubectl create configmap web-config \
  --from-literal=ENV=production \
  --from-literal=LOG_LEVEL=info \
  --from-literal=MAX_CONNECTIONS=100
```

### From a file

```bash
kubectl create configmap nginx-config \
  --from-file=nginx.conf

# or with a specific key
kubectl create configmap nginx-config \
  --from-file=server.conf=nginx.conf
```

### From a directory

```bash
# all files in ./config/ become keys
kubectl create configmap app-config \
  --from-file=./config/
```

### From env file

```bash
# .env file format: KEY=VALUE per line
kubectl create configmap app-config \
  --from-env-file=.env
```

### Declarative (YAML)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-config
  namespace: default
data:
  ENV: production
  LOG_LEVEL: info
  MAX_CONNECTIONS: "100"
binaryData:
  # for binary values, base64-encode them
  # decoded automatically when used as a volume
  cert: <base64-encoded-cert>
```

**Keys must be valid DNS subdomain names** (`a-z0-9_.-`, no slashes). Values are strings (or base64 for `binaryData`).

## Consuming a ConfigMap

### As environment variables

```yaml
env:
- name: ENV
  valueFrom:
    configMapKeyRef:
      name: web-config
      key: ENV
- name: LOG_LEVEL
  valueFrom:
    configMapKeyRef:
      name: web-config
      key: LOG_LEVEL
```

This injects `ENV=production` and `LOG_LEVEL=info` as environment variables.

### As all env vars from a ConfigMap

```yaml
envFrom:
- configMapRef:
    name: web-config
```

All keys from `web-config` become environment variables. Fast to write, but you lose control over which vars are injected.

### As a file in a volume

```yaml
volumes:
- name: config
  configMap:
    name: web-config
volumeMounts:
- name: config
  mountPath: /etc/config
```

This creates files in `/etc/config/`:

```
/etc/config/ENV         → "production"
/etc/config/LOG_LEVEL   → "info"
/etc/config/MAX_CONNECTIONS → "100"
```

The app reads these as files. Useful for config files (nginx.conf, app.properties, etc.).

### As a single file from a specific key

```yaml
volumes:
- name: nginx-conf
  configMap:
    name: nginx-config
    items:
    - key: nginx.conf
      path: default.conf
volumeMounts:
- name: nginx-conf
  mountPath: /etc/nginx/conf.d
  readOnly: true
```

This mounts `nginx.conf` from the ConfigMap as `/etc/nginx/conf.d/default.conf`.

### As command-line arguments

```yaml
command: ['/app/server']
args:
- '$(ENV)'
- '$(LOG_LEVEL)'
```

The env var substitution happens before the command runs. Note the `$(VAR)` syntax (not `$VAR`).

## The subPath gotcha

```yaml
volumeMounts:
- name: config
  mountPath: /etc/config
  subPath: ENV          # WRONG — won't get updates
```

`subPath` **breaks ConfigMap updates**. When you use `subPath`, the file is copied at Pod startup, not symlinked. Subsequent ConfigMap changes are not reflected.

**Don't use `subPath` with ConfigMap volume mounts** unless you don't need updates (immutable ConfigMaps are fine with `subPath`).

Workaround: mount the whole directory, or use an init container to copy the file.

## The env var update gotcha

ConfigMaps consumed as **environment variables are not updated automatically**. If you update the ConfigMap, existing Pods don't see the change.

```bash
# update the ConfigMap
kubectl patch configmap web-config -p '{"data":{"LOG_LEVEL":"debug"}}'

# existing Pods still have LOG_LEVEL=info
# you need to restart the Pods to pick up the change
kubectl rollout restart deployment web
```

The workaround is to restart Pods (which re-reads the env vars from the ConfigMap at startup). For Deployments, `kubectl rollout restart` does this.

**If you need dynamic updates, use a volume mount** (not env vars). Volume mounts are updated by the kubelet, typically within 60 seconds of the ConfigMap changing.

## The 1 MiB limit

ConfigMaps have a **1 MiB size limit**. You can't store large files (certificates, JARs, etc.) in a ConfigMap.

```bash
# check the size
kubectl get configmap my-config -o json | wc -c
# if > 1 MiB, the API server rejects it
```

For large data, use:

* **Secrets** — also 1 MiB, but encrypted at rest
* **A volume from a Secret** — same limit, but encrypted
* **An external config store** (S3, etcd, Consul) — no k8s limit
* **A ConfigMap with a reference to a URL** — not built-in, but some tools do this

## Immutable ConfigMaps

If a ConfigMap never changes, mark it immutable:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-config
data:
  ENV: production
immutable: true
```

Immutable ConfigMaps:

* Cannot be updated or deleted (unless you remove the `immutable` field first)
* The API server skips watching for changes (slight performance benefit)
* Are safe for `subPath` (since they never change)

Use immutable ConfigMaps for configuration that really doesn't change (feature flags, environment names, etc.).

## Namespace and RBAC

ConfigMaps are **namespace-scoped**. They can only be used by Pods in the same namespace.

```bash
# check who can read the ConfigMap
kubectl auth can-i get configmaps/web-config --namespace=default
# yes

# check if a specific SA can read it
kubectl auth can-i get configmaps/web-config \
  --namespace=default \
  --as=system:serviceaccount:production:web-app
# no
```

RBAC for ConfigMaps:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: web-config-reader
  namespace: default
rules:
- apiGroups: [""]
  resources: [configmaps]
  verbs: [get, list]
  resourceNames: [web-config]   # can only read this specific ConfigMap
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: web-config-reader
  namespace: default
subjects:
- kind: ServiceAccount
  name: web-app
  namespace: production
roleRef:
  kind: Role
  name: web-config-reader
  apiGroup: rbac.authorization.k8s.io
```

## Version skew and ConfigMaps

ConfigMaps are read at container startup. If the ConfigMap changes between when the Pod was created and when it restarts, the Pod sees the new values (for volumes) or the old values (for env vars).

For env vars: the value is snapshot at startup. Changing the ConfigMap after Pod creation doesn't affect running Pods.

For volumes: the kubelet checks for ConfigMap updates and updates the mounted files within ~60 seconds.

## Common patterns

### Multiple environments

```yaml
# base ConfigMap (shared)
---
apiVersion: v1
kind: ConfigMap
metadata: { name: app-config-base }
data:
  LOG_LEVEL: info
  CACHE_TTL: "300"
---
# production ConfigMap (extends base)
---
apiVersion: v1
kind: ConfigMap
metadata: { name: app-config-prod }
data:
  ENV: production
  LOG_LEVEL: warn
  CACHE_TTL: "600"
```

The Deployment uses `configMapRef` to pick which one. You swap ConfigMaps by changing the Deployment's envFrom.

### Config files

```bash
# nginx.conf as a ConfigMap
kubectl create configmap nginx-conf --from-file=nginx.conf=./nginx.conf
```

```yaml
volumes:
- name: nginx-conf
  configMap:
    name: nginx-conf
    items:
    - key: nginx.conf
      path: default.conf
volumeMounts:
- name: nginx-conf
  mountPath: /etc/nginx/conf.d
  readOnly: true
```

### Feature flags

```yaml
data:
  FEATURE_NEW_UI: "true"
  FEATURE_BETA_API: "false"
  FEATURE_DARK_MODE: "true"
```

Apps read these as env vars and gate behavior accordingly. This is a common pattern for gradual rollouts.

### Database connection info

```yaml
data:
  DB_HOST: postgres.database.svc.cluster.local
  DB_PORT: "5432"
  DB_NAME: myapp
  DB_USER: myapp_user
  # DB_PASSWORD goes in a Secret, not a ConfigMap
```

Credentials go in a Secret, not a ConfigMap. Non-sensitive connection info goes in a ConfigMap.

## ConfigMap vs Secret

| | ConfigMap | Secret |
|---|---|---|
| Encryption at rest | No | Yes (at rest in etcd) |
| Encoding | Plain text (or base64 in `binaryData`) | Base64 (or more with encryption providers) |
| Use case | Non-sensitive config | Credentials, certificates, tokens |
| Size limit | 1 MiB | 1 MiB |
| Same consumption | env vars, volumes | env vars, volumes |

**A Secret is not truly secure** — it's base64-encoded, not encrypted, in etcd. For real secrets, use an external secrets manager (HashiCorp Vault, AWS Secrets Manager, etc.) with a CSI driver or operator.

## The static Pod limitation

**Static Pods cannot reference ConfigMaps.** A static Pod is managed directly by the kubelet, not by the API server. Since the kubelet doesn't have access to the API server's ConfigMap data, it can't inject it.

Workaround: bake the config into the file on disk (e.g. via an init script), or use the API server (don't use static Pods).

## See also

* [[Kubernetes/concepts/L05-config-storage/02-secrets|Secrets]] — for sensitive data
* [[Kubernetes/concepts/L03-workloads/01-pods|Pods]] — how ConfigMaps are consumed in Pod specs
* [[Kubernetes/concepts/L05-config-storage/08-resource-quota|Resource Quotas]] — namespace-level limits on ConfigMaps