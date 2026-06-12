---
title: Argo CD Operator Install
tags:
  - Kubernetes
  - GitOps
  - Argo CD
  - Operator
---

How to install and configure Argo CD in production. The install is one thing; the production-grade configuration is another. This covers the HA install, the RBAC, the SSO, the notifications, and the integration patterns that make Argo CD work at scale.

## The install decision tree

```
Q: Production or dev?
│
├── dev
│   └── quick install: kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
│
└── production
    │
    Q: HA or single instance?
    │
    ├── single
    │   └── install.yaml with 1 replica, 1 Redis
    │
    └── HA
        │
        ├── HA install.yaml (3+ replicas, 3 Redis, 3 repo-server)
        │
        └── Helm chart (recommended for HA)
            │
            ├── argocd-image-updater
            ├── argocd-notifications
            └── SSO integration
```

**For production, use Helm + HA + SSO.** Everything else is a footgun.

## The quick install (dev only)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

That's it. Argo CD is up. Web UI on port 80 of the argocd-server Service.

**Don't use this in production.** Single instance of everything. No HA. No SSO. No notifications.

## The production install (Helm)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

```yaml
# values.yaml
global:
  domain: argocd.example.com
  # set in production to enable TLS
  # and SSO redirects

redis:
  enabled: true
  architecture: replication    # 3 instances, not 1
  sentinel:
    enabled: false             # use the replication pattern

controller:
  enabled: true
  replicas: 3                  # HA controller
  metrics:
    enabled: true
  resources:
    requests:
      cpu: 1
      memory: 2Gi
    limits:
      cpu: 4
      memory: 4Gi

server:
  enabled: true
  replicas: 3                  # HA server
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 5
  metrics:
    enabled: true
  service:
    type: ClusterIP
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/backend-protocol: HTTPS
    hosts:
    - argocd.example.com
    tls:
    - hosts:
      - argocd.example.com
      secretName: argocd-server-tls

repoServer:
  enabled: true
  replicas: 3                  # HA repo server
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 5
  metrics:
    enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 1Gi

applicationSet:
  enabled: true                # for ApplicationSets

dex:
  enabled: false               # we're using SSO via OIDC, not Dex

configs:
  cm:
    # the central config
    url: https://argocd.example.com
    additionalApplications: []
    resource.customizations.health.lua: |
      -- custom health check
    resource.exclusions: |
      - apiGroups:
        - cilium.io
        kinds:
        - CiliumIdentity
        clusters:
        - '*'

  params:
    server.insecure: false
    server.disable.auth: false

  rbac:
    defaultPolicy: 'role:readonly'
    policyMatcherMode: 'glob'
    scopes: '[groups, email]'
    policy.default: 'role:readonly'

  secrets:
    # OIDC client secret
    oidc.clientSecret: ...

  styles: |
    .my-custom-style { ... }
```

```bash
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --values values.yaml
```

## The HA install (manifests)

The HA install uses StatefulSets, multiple replicas, and 3 Redis instances:

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/ha/manifests/install.yaml
```

**What HA gives you:**
- 3 controller replicas (1 leader, 2 standby)
- 3 Redis instances (1 master, 2 replicas)
- 3 repo-server replicas
- 3 application controller replicas

**Trade-off:** more resources. The HA install needs ~4GB RAM, 4 CPU minimum.

## Initial setup

### Get the initial admin password

```bash
# the auto-generated password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Login via CLI

```bash
argocd login argocd.example.com --grpc-web

# or
argocd login argocd.example.com --sso
```

### Change admin password

```bash
argocd account update-password \
  --account admin \
  --current-password <old> \
  --new-password <new>
```

### Add a repo

```bash
argocd repo add https://github.com/myorg/myapp \
  --username myuser \
  --password <token>
```

Or in the UI: Settings → Repositories → Connect Repo.

## SSO integration

Argo CD supports OIDC out of the box.

```yaml
# values.yaml (configmap section)
configs:
  cm:
    url: https://argocd.example.com
    oidc.config: |
      name: Okta
      issuer: https://example.okta.com
      clientId: xxx
      clientSecret: $oidc.clientSecret
      requestedScopes:
      - openid
      - profile
      - email
      - groups
      groupsClaim: groups
```

```yaml
# values.yaml (secrets section)
configs:
  secrets:
    oidc.clientSecret: <your-client-secret>
```

The OIDC client in Okta/Keycloak/etc. needs:
- Redirect URI: `https://argocd.example.com/auth/callback`
- Grant type: Authorization Code
- Scopes: openid, profile, email, groups

### OIDC with group-based RBAC

```yaml
configs:
  rbac:
    policy.default: 'role:readonly'
    scopes: '[groups, email]'
    policyMatcherMode: 'glob'
```

```yaml
# policy.csv
p, role:admin, applications, *, */*, allow
p, role:readonly, applications, get, */*, allow

g, sre-team, role:admin
g, dev-team, role:readonly
```

Users in `sre-team` group get admin. Users in `dev-team` get readonly.

## Notifications

Argo CD can send notifications on sync events.

```yaml
# argocd-notifications-cm
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
  template.app-deployed: |
    message: |
      Application {{.app.metadata.name}} is now running on {{.app.status.sync.revision}}.
      {{if eq .app.status.health.status "Healthy"}}✅{{else}}⚠️{{end}}
    slack:
      attachments: |
        [{"color": "good", "fields": [{"title": "App", "value": "{{.app.metadata.name}}"}]}]
  trigger.on-deployed: |
    - when: app.status.sync.status == 'Synced' and app.status.health.status == 'Healthy'
      send: [app-deployed]
```

```yaml
# argocd-notifications-secret
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
stringData:
  slack-token: <slack-bot-token>
```

Subscribe an app:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.slack: my-channel
```

## Projects (multi-tenancy)

Argo CD Projects are like namespaces for Argo CD — they group applications, restrict what they can deploy, and enforce RBAC.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-a
  namespace: argocd
spec:
  description: Team A's applications
  
  # source repos
  sourceRepos:
  - https://github.com/myorg/team-a-*
  
  # destination clusters + namespaces
  destinations:
  - namespace: team-a-*
    server: '*'
  
  # cluster resources allowed
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  
  # namespace resources allowed
  namespaceResourceWhitelist:
  - group: ''
    kind: '*'
  
  # sync windows (when syncing is allowed)
  syncWindows:
  - kind: deny
    schedule: '0 0 * * 5'    # deny on Friday
    duration: 24h
    applications:
    - '*-prod'
  
  # roles (RBAC)
  roles:
  - name: developer
    policies:
    - p, proj:team-a:developer, applications, get, team-a/*, allow
    - p, proj:team-a:developer, applications, sync, team-a/*, allow
    groups:
    - team-a-developers
  
  - name: admin
    policies:
    - p, proj:team-a:admin, applications, *, team-a/*, allow
    groups:
    - team-a-admins
```

**For tenant isolation:** projects prevent team-a from deploying to team-b's namespace.

## ApplicationSets (templated apps)

For deploying the same app to many clusters/environments:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: prod-us
        url: https://prod-us.example.com
      - cluster: prod-eu
        url: https://prod-eu.example.com
  template:
    metadata:
      name: 'addons-{{cluster}}'
    spec:
      project: infrastructure
      source:
        repoURL: https://github.com/myorg/cluster-addons
        targetRevision: HEAD
        path: 'overlays/{{cluster}}'
      destination:
        server: '{{url}}'
        namespace: kube-system
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

One ApplicationSet, many Applications, one per cluster.

## The Image Updater

Argo CD Image Updater watches registries and updates image tags in git (or in-cluster).

```bash
helm install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --set serverAddr=argocd-server.argocd.svc.cluster.local:443 \
  --set args.enable-kubernetes=false \
  --set args.enable-helm=false \
  --set credentials="git-creds"
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  annotations:
    argocd-image-updater.argoproj.io/image-list: myapp=myregistry/myapp
    argocd-image-updater.argoproj.io/myapp.update-strategy: latest
    argocd-image-updater.argoproj.io/myapp.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$
    argocd-image-updater.argoproj.io/git-branch: main
spec:
  # ...
```

Image Updater opens PRs with new image tags. No CI needed.

## Backup and restore

Argo CD state is in 2 places:
- **Configuration:** Application manifests, Projects (in git)
- **State:** Sync status, history (in Redis)

**Git is the source of truth for configuration.** If you lose Redis, the controller re-syncs from git.

```bash
# export the state
argocd admin export -n argocd > argocd-backup.yaml

# import (in a new cluster)
argocd admin import -n argocd --filename argocd-backup.yaml
```

For full backup, snapshot the Redis instances and etcd.

## Disaster recovery

Argo CD's CRDs are in the cluster. If the cluster is gone:

1. **Re-install Argo CD** from Helm
2. **Re-create the cluster secret** (the cluster definition)
3. **Argo CD will resync** from the configured git repos

**The git repos are the source of truth.** The cluster is just a runtime.

## Performance tuning

### Increase controller resources

The controller can be slow for large numbers of apps. Increase resources:

```yaml
controller:
  resources:
    requests:
      cpu: 4
      memory: 8Gi
    limits:
      cpu: 8
      memory: 16Gi
```

### Sharding controller

For 1000+ apps, shard the controller:

```yaml
# argocd-controller-shard-cm
data:
  controller.sharding.algorithm: round-robin
  controller.sharding.replicas: "3"
```

Each controller instance handles a subset of apps.

### ApplicationSet for many apps

ApplicationSet can generate many Applications from a template. For 100+ apps:

```yaml
generators:
- list:
    elements:
    - app: app1
    - app: app2
    - ...
    - app: app100
```

### Repository caching

```yaml
# argocd-cm
data:
  timeout.reconciliation: 30s
  status.processors: 20
  controller.repo.server.timeout.seconds: 60
```

### Parallelism

```yaml
controller:
  env:
  - name: ARGOCD_CONTROLLER_REPLICAS
    value: "3"
  - name: ARGOCD_CONTROLLER_PARALLELISM_LIMIT
    value: "10"
```

## Common gotchas

* **Application CRDs must be in the cluster.** If you delete them, all apps become orphan.
* **The initial admin password** is stored in a Secret that's auto-deleted. Save it.
* **`argocd-server --insecure`** is fine for dev, not for production. Use TLS.
* **RBAC requires OIDC or SAML.** Local users don't get group-based RBAC.
* **Argo CD's ServiceAccount** has wide cluster permissions. Restrict via Projects.
* **Sync windows can lock you out.** A "deny on Friday" sync window means no auto-sync on Friday.
* **Image Updater needs git credentials.** The Secret must be in `argocd` namespace.
* **The CLI is `argocd`**, not `kubectl-argocd`. Install it from argocd-cli.
* **ApplicationSet requires CRDs.** Helm install doesn't always include them; check.
* **Self-heal deletes manual changes.** The controller reverts kubectl edits.
* **The HA install is resource-hungry.** Don't try to run it on small clusters.

## See also

* [[Kubernetes/guides/delivery/gitops/basics|gitops-basics]] — the model
* [[Kubernetes/guides/non-functional/oidc-integration|oidc-integration]] — auth for Argo CD
* [[Kubernetes/guides/non-functional/security-baseline|security-baseline]] — RBAC
* [Argo CD operator docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/)
