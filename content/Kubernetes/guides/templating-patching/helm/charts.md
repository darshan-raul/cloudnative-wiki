---
title: Helm Charts
tags: [kubernetes, helm, charts, templates]
date: 2026-05-16
description: Chart structure, templates, values, dependencies, and hooks
---

# Helm Charts

Charts are the packaging format for Helm. A chart is a collection of files that describe a related set of Kubernetes resources.

## Chart File Structure

```
mychart/
├── Chart.yaml              # Required: Chart metadata
├── LICENSE                 # Optional: License file
├── README.md               # Optional: README
├── values.yaml             # Default configuration values
├── values.schema.json      # Optional: JSON Schema for values validation
├── charts/                 # Directory for chart dependencies
├── crds/                   # Custom Resource Definitions
└── templates/              # Directory for Kubernetes manifests
    ├── NOTES.txt           # Optional: Usage notes (rendered post-install)
    ├── _helpers.tpl        # Optional: Helper templates
    ├── _configmap.tpl      # Optional: Additional helpers
    └── deployment.yaml     # Kubernetes resources
```

## Chart.yaml

The `Chart.yaml` file is required for every chart.

```yaml
apiVersion: v2                  # Chart API version (v2 for Helm 3+)
name: mychart                   # Chart name
version: 1.2.3                  # Chart version (SemVer 2)
kubeVersion: ">=1.21.0"         # Optional: Compatible Kubernetes versions
description: A Helm chart      # Single-sentence description
type: application               # application or library
keywords:
  - web
  - application
home: https://example.com       # Project homepage
sources:
  - https://github.com/example/mychart
maintainers:                    # Optional: Chart maintainers
  - name: John Doe
    email: john@example.com
    url: https://example.com
icon: https://example.com/icon.png
appVersion: "1.0.0"            # Application version (informational)
deprecated: false               # Mark chart as deprecated
annotations:
  category: web
```

### Chart Types

```yaml
# Application chart (default) - standard deployable chart
type: application

# Library chart - provides utilities/functions, not installable
type: library
```

### Dependencies

```yaml
dependencies:
  - name: nginx
    version: "1.2.3"
    repository: "https://charts.bitnami.com"
    # Or use alias
    alias: web-server

  - name: redis
    version: ">=2.0.0"
    repository: "https://charts.bitnami.com"
    condition: redis.enabled      # Enable/disable based on values
    tags:
      - cache
      - database

  # Using repository alias (先 helm repo add --alias stable https://charts.helm.sh/stable)
  - name: postgresql
    version: "12.x.x"
    repository: "@stable"

  # OCI registry dependency
  - name: common-lib
    version: "1.0.0"
    repository: "oci://ghcr.io/org/charts"
```

## Values Schema (values.schema.json)

Enforce structure on values.yaml:

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "properties": {
    "image": {
      "type": "object",
      "properties": {
        "repository": { "type": "string" },
        "tag": { "type": "string" },
        "pullPolicy": { "type": "string", "enum": ["IfNotPresent", "Always", "Never"] }
      },
      "required": ["repository"]
    },
    "replicaCount": {
      "type": "integer",
      "minimum": 1,
      "maximum": 10
    },
    "service": {
      "type": "object",
      "properties": {
        "port": { "type": "integer", "minimum": 1, "maximum": 65535 },
        "type": { "type": "string", "enum": ["ClusterIP", "NodePort", "LoadBalancer"] }
      },
      "required": ["port"]
    }
  },
  "required": ["image", "service"],
  "title": "Values",
  "type": "object"
}
```

## values.yaml

Default configuration values:

```yaml
# Simple values
replicaCount: 1
image:
  repository: nginx
  tag: "1.21"
  pullPolicy: IfNotPresent

# Nested configuration
service:
  type: ClusterIP
  port: 80

# List values
ingress:
  hosts:
    - host: app.example.com
      paths:
        - path: /
          pathType: Prefix

# Global values (accessible from subcharts)
global:
  imageRegistry: docker.io
  storageClass: standard

# Environment-specific (use -f to override)
environment: dev
```

### Value Precedence (later wins)

1. Chart's values.yaml (defaults)
2. Parent chart's values.yaml
3. `-f` values files (left to right)
4. `--set` values (command line)

## Template Functions & Pipelines

Helm uses Go templates with Sprig functions.

### Common Functions

```yaml
# String operations
name: {{ .Values.name | quote }}
name: {{ .Values.name | upper }}
name: {{ .Values.name | lower }}
name: {{ .Values.name | trim }}
name: {{ .Values.name | default "default-value" }}

# Math
replicas: {{ .Values.replicaCount | int }}

# Conditional
replicas: {{ if eq .Values.environment "production" }}3{{ else }}1{{ end }}

# Required (fail if missing)
image: {{ required "image.repository is required" .Values.image.repository }}

# Include template
{{ include "mychart.labels" . }}

# tpl (render string as template)
config: {{ tpl .Values.configTemplate . }}
```

### Debugging Templates

```bash
# Dry-run with debug output
helm install --dry-run --debug myapp ./mychart

# Template locally
helm template myapp ./mychart

# Lint chart
helm lint ./mychart
```

## Named Templates (Partials)

Create reusable template snippets in `templates/_*.tpl`.

### _helpers.tpl

```yaml
{{/* Expand the name of the chart */}}
{{- define "mychart.name" -}}
{{- default .Chart.Name .Values.nameOverride | printf "%s-%s" .Release.Name -}}
{{- end }}

{{/* Common labels */}}
{{- define "mychart.labels" -}}
app.kubernetes.io/name: {{ include "mychart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* Selector labels */}}
{{- define "mychart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mychart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

### Using Helpers in Templates

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.name" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "mychart.selectorLabels" . | nindent 8 }}
```

## Accessing Files in Templates

### .Files object

```yaml
# Get file content
{{ .Files.Get "config.json" }}

# Get file as lines
{{ .Files.Lines "config.ini" }}

# Check if file exists
{{ if .Files.Get "config.yaml" }}...{{ end }}

# Glob files
{{ range $key, $value := .Files.Glob "configs/*.yaml" }}
- {{ $key }}: {{ $value }}
{{ end }}
```

### Include file content in ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "mychart.name" . }}
data:
  config.yaml: |
    {{ .Files.Get "configs/config.yaml" | indent 4 }}
```

## Hooks

Chart hooks run Jobs at specific points in release lifecycle.

### Hook Annotations

```yaml
metadata:
  annotations:
    helm.sh/hook: pre-install,post-install    # Multiple hooks
    helm.sh/hook-weight: "5"                # Execution order (negative to positive)
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
```

### Available Hooks

| Hook | When it runs |
|------|--------------|
| `pre-install` | After templates rendered, before resources created |
| `post-install` | After all resources loaded into Kubernetes |
| `pre-delete` | Before any resources deleted |
| `post-delete` | After all resources deleted |
| `pre-upgrade` | After templates rendered, before resources updated |
| `post-upgrade` | After all resources upgraded |
| `pre-rollback` | After templates rendered, before resources rolled back |
| `post-rollback` | After all resources modified |
| `test` | When `helm test` is invoked |

### Hook Delete Policies

```yaml
annotations:
  helm.sh/hook-delete-policy: |
    before-hook-creation    # Delete old hook before new one (default)
    hook-succeeded          # Delete after successful run
    hook-failed              # Delete if hook fails
```

### Example: Backup Job Hook

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: "{{ .Release.Name }}-backup"
  annotations:
    helm.sh/hook: pre-upgrade
    helm.sh/hook-weight: "-5"                  # Run early
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: backup
          image: busybox
          command: ["/bin/sh", "-c", "echo backing up"]
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: {{ .Release.Name }}-data
```

### Example: Database Migration Hook

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: "{{ .Release.Name }}-migrate"
  annotations:
    helm.sh/hook: post-install,post-upgrade
    helm.sh/hook-weight: "10"
    helm.sh/hook-delete-policy: hook-succeeded
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          command: ["python", "manage.py", "migrate"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: {{ .Release.Name }}-db
                  key: url
```

## Subcharts and Global Values

### Subchart Structure

```
mychart/
├── Chart.yaml
├── values.yaml
└── charts/
    └── common/
        ├── Chart.yaml
        ├── templates/
        └── values.yaml
```

### Accessing Subchart Values

```yaml
# Parent values.yaml
common:
  imageRegistry: docker.io

subchart:
  enabled: true
  replicaCount: 2

# Subchart values.yaml
imageRegistry: ""        # Gets overridden
replicaCount: 1

# Access global in subchart
image: {{ .Values.global.imageRegistry }}/nginx
```

### Importing Subchart Values

```yaml
# Parent Chart.yaml - using exports format
dependencies:
  - name: common
    version: "1.0.0"
    repository: "https://charts.example.com"
    import-values:
      - data

# Child values.yaml with exports
exports:
  data:
    sharedKey: shared-value
    enabled: true
```

### Child-Parent Format

```yaml
# Parent Chart.yaml
dependencies:
  - name: subchart
    import-values:
      - child: default.data
        parent: imports
```

## Custom Resource Definitions (CRDs)

### CRDs Directory

Place CRD files in `crds/` directory:

```
mychart/
├── crds/
│   ├── crontab.yaml
│   └── custom-resource.yaml
```

### CRD Installation Behavior

- CRDs are installed before regular templates
- CRDs are never reinstalled (already present = skip)
- CRDs are never deleted on upgrade/rollback
- CRDs are never deleted on uninstall

### CRD Template Example

```yaml
# crds/mycrd.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: crontabs.stable.example.com
spec:
  group: stable.example.com
  versions:
    - name: v1
      served: true
      storage: true
  scope: Namespaced
  names:
    plural: crontabs
    singular: crontab
    kind: CronTab
```

### Use CRD in Templates

```yaml
# templates/mycrontab.yaml
apiVersion: stable.example.com/v1
kind: CronTab
metadata:
  name: {{ .Release.Name }}
spec:
  cron: "{{ .Values.schedule }}"
  image: {{ .Values.image }}
```

## NOTES.txt

Short usage notes displayed after install/upgrade:

```yaml
# templates/NOTES.txt
Thank you for installing {{ .Chart.Name }}.

Your application is ready.

Application URL: http://{{ .Release.Name }}.{{ .Values.ingress.host }}

To learn more:
- View pods: kubectl get pods -l app={{ include "mychart.name" . }}
- View logs: kubectl logs -l app={{ include "mychart.name" . }}
- Upgrade: helm upgrade {{ .Release.Name }} {{ .Chart.Name }} -f values.yaml
```

## .helmignore

Exclude files from chart package:

```yaml
# .helmignore
# Patterns
.git
.gitignore
*.md
docs/
tests/
ci/
.env
*.log

# Directories
tmp/
.idea/
.vscode/
charts/

# Files
secrets.yaml
credentials.json
```

## Complete Example

### Chart.yaml

```yaml
apiVersion: v2
name: webapp
version: 1.0.0
appVersion: "2.1"
description: Web application chart
kubeVersion: ">=1.21"
type: application
keywords:
  - web
  - http
maintainers:
  - name: DevOps Team
    email: devops@example.com
dependencies:
  - name: common
    version: "1.x.x"
    repository: "https://charts.bitnami.com"
```

### values.yaml

```yaml
replicaCount: 2

image:
  repository: nginx
  tag: "1.21"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  className: nginx
  host: app.example.com
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod

resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

config:
  logLevel: info
  maxConnections: 1000
```

### templates/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "webapp.name" . }}
  labels:
    {{- include "webapp.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "webapp.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "webapp.selectorLabels" . | nindent 8 }}
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      containers:
        - name: webapp
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.port }}
              name: http
          env:
            - name: LOG_LEVEL
              value: {{ .Values.config.logLevel }}
            - name: MAX_CONNECTIONS
              value: {{ .Values.config.maxConnections | quote }}
          livenessProbe:
            httpGet:
              path: /health
              port: http
          readinessProbe:
            httpGet:
              path: /ready
              port: http
          resources:
            {{- toYaml .Values.resources | nindent 10 }}
```