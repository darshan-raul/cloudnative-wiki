---
title: Helm Library Charts
tags: [kubernetes, helm, library-charts, code-reuse]
date: 2026-05-16
description: Creating and using library charts for shared templates
---

# Helm Library Charts

Library charts provide reusable templates and utilities that can be shared across multiple charts. They are not installable on their own.

## Overview

A library chart is a type of Helm chart that:

- Defines chart primitives or shared definitions
- Cannot be deployed independently
- Is included as a dependency by application charts
- Allows template code reuse across charts

## Creating a Library Chart

### 1. Create Chart Structure

```bash
helm create common-lib --type library
```

This creates:

```
common-lib/
├── Chart.yaml
├── templates/
└── values.yaml
```

### 2. Configure as Library

```yaml
# Chart.yaml
apiVersion: v2
name: common-lib
description: Common library chart with shared templates
type: library
version: 1.0.0
appVersion: "1.0.0"
```

### 3. Remove Installable Resources

Delete all template files and start fresh:

```bash
rm -rf common-lib/templates/*
```

### 4. Create Shared Templates

#### _configmap.tpl

```yaml
{{/* Common ConfigMap template */}}
{{- define "common.configmap" -}}
{{- $fullName := include "common.fullname" . -}}
{{- $labels := include "common.labels" . -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $fullName }}
  labels:
    {{- $labels | nindent 4 }}
{{- end -}}
```

#### _deployment.tpl

```yaml
{{/* Common Deployment template */}}
{{- define "common.deployment" -}}
{{- $name := include "common.fullname" . -}}
{{- $labels := include "common.labels" . -}}
{{- $selector := include "common.selectorLabels" . -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $name }}
  labels:
    {{- $labels | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount | default 1 }}
  selector:
    matchLabels:
      {{- $selector | nindent 6 }}
  template:
    metadata:
      labels:
        {{- $selector | nindent 8 }}
{{- end -}}
```

#### _service.tpl

```yaml
{{/* Common Service template */}}
{{- define "common.service" -}}
{{- $name := include "common.fullname" . -}}
{{- $labels := include "common.labels" . -}}
{{- $selector := include "common.selectorLabels" . -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ $name }}
  labels:
    {{- $labels | nindent 4 }}
spec:
  type: {{ .Values.service.type | default "ClusterIP" }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort | default "http" }}
      protocol: TCP
      name: http
  selector:
    {{- $selector | nindent 4 }}
{{- end -}}
```

#### _helpers.tpl

```yaml
{{/* Full name (release-chart) */}}
{{- define "common.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | printf "%s" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Full labels including release info */}}
{{- define "common.labels" -}}
app.kubernetes.io/name: {{ include "common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* Selector labels (for pod selector) */}}
{{- define "common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Chart name */}}
{{- define "common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Merge utility - merges two YAML maps */}}
{{- define "common.merge" -}}
{{- $overrides := .Values | deepCopy -}}
{{- toYaml (merge $overrides (include .template $.context | fromYaml)) -}}
{{- end -}}
```

#### _util.yaml

```yaml
{{/* Utility: Merge two YAML templates */}}
{{- define "util.merge" -}}
{{- $top := first . -}}
{{- $overrides := fromYaml (include (index . 1) $top) | default dict -}}
{{- $tpl := fromYaml (include (index . 2) $top) | default dict -}}
{{- toYaml (merge $overrides $tpl) -}}
{{- end -}}

{{/* Utility: Conditional default */}}
{{- define "util.default" -}}
{{- if empty (index .Values (index . 1)) -}}
{{- print (index . 2) -}}
{{- else -}}
{{- print (index .Values (index . 1)) -}}
{{- end -}}
{{- end -}}
```

## Using Library Charts

### Add as Dependency

```yaml
# Chart.yaml
dependencies:
  - name: common-lib
    version: "1.x.x"
    repository: "file://../common-lib"
    # Or from registry:
    # repository: "oci://ghcr.io/org/charts/common-lib"
```

### Run Dependency Update

```bash
helm dependency update ./myapp
```

### Use Shared Templates

```yaml
# templates/configmap.yaml
{{- include "common-lib.configmap" (list . "myapp.configmap") -}}
{{- define "myapp.configmap" -}}
data:
  app.ini: |
    [settings]
    log_level = {{ .Values.config.logLevel | default "info" }}
    max_connections = {{ .Values.config.maxConnections | default 1000 }}
{{- end -}}
```

### Override Defaults

```yaml
# templates/deployment.yaml
{{- $ctx := dict "Release" .Release "Chart" .Chart "Values" .Values "Template" .Template -}}
{{- $deployment := include "common-lib.deployment" $ctx -}}
{{- $tpl := fromYaml $deployment -}}
{{- $_ := set $tpl.spec "replicas" .Values.replicaCount -}}
{{- $_ := set $tpl.spec.template.spec "restartPolicy" "Always" -}}
{{- toYaml $tpl | nindent 0 -}}
```

## Utility Functions for Library Charts

### DeepMerge

```yaml
{{/* _utils.tpl */}}
{{/* Deep merge two YAML structures */}}
{{- define "utils.deepMerge" -}}
{{- $dst := index . 0 -}}
{{- $src := index . 1 -}}
{{- if kindOf "map" eq $dst }}
{{- range $key, $value := $src }}
{{- if and (hasKey $dst $key) (kindIs "map" (index $dst $key)) }}
{{- $_ := set $dst $key (include "utils.deepMerge" (list (index $dst $key) $value)) }}
{{- else }}
{{- $_ := set $dst $key $value }}
{{- end }}
{{- end }}
{{- end }}
{{- toYaml $dst -}}
{{- end -}}
```

### Template Include with Context

```yaml
{{/* _utils.tpl */}}
{{/* Include template with modified context */}}
{{- define "utils.withValues" -}}
{{- $values := index . 1 -}}
{{- $template := index . 0 -}}
{{- $ctx := merge .Values $values -}}
{{- include $template (dict "Values" $ctx "Release" .Release "Chart" .Chart "Template" .Template) -}}
{{- end -}}
```

## Best Practices

### 1. Use Named Templates with Prefix

```yaml
# Prefix with chart name to avoid conflicts
{{- define "common-lib.configmap" -}}
# ...
{{- end -}}

{{- define "common-lib.deployment" -}}
# ...
{{- end -}}
```

### 2. Provide Default Values

```yaml
# values.yaml in library chart
replicaCount: 1

image:
  repository: nginx
  tag: "latest"

service:
  type: ClusterIP
  port: 80

config:
  logLevel: info
```

### 3. Document Template Usage

```yaml
# _README.md in templates/
{{/*
Common utility templates for Kubernetes resources.

Usage:
  {{ include "common-lib.configmap" (list . "myapp.configmap") }}

  {{- define "myapp.configmap" -}}
  data:
    key: value
  {{- end -}}
*/}}
```

### 4. Version Carefully

```yaml
# Library chart should follow SemVer strictly
version: 1.0.0  # Major for breaking changes
version: 1.1.0  # Minor for new features
version: 1.0.1  # Patch for bug fixes
```

### 5. Test Library Charts

```yaml
# templates/tests/configmap_test.yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "common-lib.fullname" . }}-test
  annotations:
    helm.sh/hook: test
spec:
  containers:
    - name: test
      image: busybox
      command: ['echo', 'Library chart works']
  restartPolicy: Never
```

## Example: Shared Monitoring Template

### common-lib/templates/_servicemonitor.tpl

```yaml
{{/* ServiceMonitor for Prometheus scraping */}}
{{- define "common.servicemonitor" -}}
{{- $name := include "common.fullname" . -}}
{{- $labels := include "common.labels" . -}}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ $name }}
  labels:
    {{- $labels | nindent 4 }}
    prometheus: {{ .Values.prometheus.scrape | default "true" }}
spec:
  jobLabel: {{ $name }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: http
      path: {{ .Values.prometheus.path | default "/metrics" }}
      interval: {{ .Values.prometheus.interval | default "30s" }}
{{- end -}}
```

### Usage in Application Chart

```yaml
# myapp/templates/servicemonitor.yaml
{{- if .Values.monitoring.enabled -}}
{{- include "common-lib.servicemonitor" . }}
{{- end -}}
```

## Installation Prevention

Library charts cannot be installed directly:

```bash
$ helm install common-lib ./common-lib
Error: library charts are not installable
```

This is intentional - they only provide utility templates for other charts.

## References

- [Official Helm Library Charts Documentation](https://helm.sh/docs/topics/library_charts/)
- [Common Helm Helper Chart](https://github.com/helm/charts/tree/master/incubator/common) (deprecated)