---
title: Argo Workflows
tags:
  - Kubernetes
  - Delivery
  - CI/CD
  - Argo Workflows
---

Argo Workflows is a **container-native workflow engine** for k8s. Each step in a workflow runs in its own pod. You get parallelism, retries, artifacts, and a DAG for free. Use it for batch jobs, ML pipelines, CI/CD, and any "run these steps in order, retry on failure" need.

## When to use Argo Workflows

**Use it for:**
- CI/CD pipelines (build, test, scan, push, deploy)
- ML training and inference pipelines
- ETL / data processing
- Scheduled batch jobs (cron workflows)
- Infrastructure automation
- Image building
- Any DAG of long-running, parallel, or retryable tasks

**Don't use it for:**
- HTTP APIs (use a service)
- Long-running services (use a Deployment)
- Simple cron jobs (use CronJob)
- Sub-second tasks (use a queue)

## The mental model

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  Workflow                                                │
│  ├── template: build                                     │
│  │   └── container: golang:1.21                          │
│  │       └── steps:                                      │
│  │           ├── checkout                                │
│  │           ├── test                                    │
│  │           └── build                                   │
│  ├── template: scan                                      │
│  │   └── container: trivy:latest                         │
│  │       └── steps:                                      │
│  │           └── scan                                    │
│  ├── template: push                                      │
│  │   └── container: buildah                             │
│  │       └── steps:                                      │
│  │           └── push                                    │
│  └── DAG:                                                │
│      build → scan → push                                 │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

Each step is a pod. Each workflow is a Kubernetes resource.

## A simple CI/CD workflow

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: build-myapp-
  namespace: argo
spec:
  entrypoint: ci-pipeline
  serviceAccountName: argo-workflow-sa
  
  templates:
  - name: ci-pipeline
    dag:
      tasks:
      - name: checkout
        template: git-checkout
      
      - name: test
        dependencies: [checkout]
        template: run-tests
      
      - name: build
        dependencies: [test]
        template: build-image
      
      - name: scan
        dependencies: [build]
        template: scan-image
      
      - name: push
        dependencies: [scan]
        template: push-image
  
  - name: git-checkout
    container:
      image: alpine/git:v2.42.0
      workingDir: /workspace
      command: [sh, -c]
      args:
      - |
        git clone --depth 1 https://github.com/myorg/myapp.git .
        git checkout $GIT_REF
        echo "checked out $GIT_REF"
      env:
      - name: GIT_REF
        value: "main"
    volumeMounts:
    - name: workspace
      mountPath: /workspace
  
  - name: run-tests
    container:
      image: myregistry/myapp:ci
      workingDir: /workspace
      command: [sh, -c]
      args: ["make test"]
    volumeMounts:
    - name: workspace
      mountPath: /workspace
  
  - name: build-image
    container:
      image: gcr.io/kaniko-project/executor:debug
      workingDir: /workspace
      command: [sh, -c]
      args:
      - |
        /kaniko/executor \
          --context /workspace \
          --dockerfile /workspace/Dockerfile \
          --destination myregistry/myapp:$BUILD_TAG \
          --cache=true
      env:
      - name: BUILD_TAG
        value: "v1.2.3"
    volumeMounts:
    - name: workspace
      mountPath: /workspace
  
  - name: scan-image
    container:
      image: aquasec/trivy:0.48.0
      command: [sh, -c]
      args:
      - trivy image --exit-code 1 --severity HIGH,CRITICAL myregistry/myapp:v1.2.3
  
  - name: push-image
    # push already done by kaniko
    container:
      image: alpine:3.19
      command: [echo, "pushed"]
  
  volumes:
  - name: workspace
    emptyDir: {}
```

**Run it:**

```bash
argo submit --serviceaccount argo-workflow-sa -n argo -f workflow.yaml
```

## The building blocks

### Steps (sequential)

```yaml
- name: sequential
  steps:
  - - name: step-1
      template: task-a
  - - name: step-2
      template: task-b
    - name: step-3
      template: task-c
  - - name: step-4
      template: task-d
```

- `-` is a sequential boundary
- Within a `-`, tasks run in parallel
- Across `-`, tasks run in sequence

So this is: step-1 → (step-2, step-3 in parallel) → step-4.

### DAG (explicit dependencies)

```yaml
- name: dag
  dag:
    tasks:
    - name: a
      template: task-a
    - name: b
      template: task-b
      dependencies: [a]
    - name: c
      template: task-task-c
      dependencies: [a]
    - name: d
      template: task-d
      dependencies: [b, c]
```

`a` runs first. `b` and `c` run after `a`, in parallel. `d` runs after `b` and `c`.

**DAG is the right choice for most workflows** — explicit, easy to read.

### Container template

```yaml
- name: simple-step
  container:
    image: alpine:3.19
    command: [sh, -c]
    args: ["echo hello"]
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi
    env:
    - name: VAR
      value: "value"
    volumeMounts:
    - name: data
      mountPath: /data
```

A single pod running the container. Most steps are this.

### Script template

```yaml
- name: script-step
  script:
    image: python:3.12
    command: [python]
    source: |
      import os
      print(f"hello {os.environ.get('NAME', 'world')}")
    env:
    - name: NAME
      value: "alice"
```

Convenience wrapper. Same as container, but writes a source script and runs it.

### Resource template

```yaml
- name: create-resource
  resource:
    action: create
    manifest: |
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: my-config
      data:
        key: value
```

Create, apply, delete, replace a k8s resource. Useful for "create this, then proceed."

### Suspend template

```yaml
- name: wait-for-approval
  suspend:
    duration: "30m"
```

Pauses the workflow. Useful for manual gates.

```yaml
- name: wait-forever
  suspend: {}
```

Pause indefinitely. Resume manually.

## Parameters and arguments

### Workflow parameters

```yaml
spec:
  entrypoint: ci
  arguments:
    parameters:
    - name: image-tag
      value: "v1.0.0"
  
  templates:
  - name: ci
    inputs:
      parameters:
      - name: image-tag
    container:
      image: alpine:3.19
      args: ["echo {{inputs.parameters.image-tag}}"]
```

Pass at submit time:

```bash
argo submit -f workflow.yaml -p image-tag=v1.2.3
```

### Outputs

```yaml
- name: produce
  outputs:
    parameters:
    - name: result
      valueFrom:
        path: /tmp/result.txt
  container:
    image: alpine:3.19
    command: [sh, -c]
    args: ["echo myresult > /tmp/result.txt"]
```

```yaml
- name: consume
  inputs:
    parameters:
    - name: prev-result
      value: "{{tasks.produce.outputs.parameters.result}}"
```

## Artifacts

For passing files between steps (vs. volumes).

```yaml
- name: producer
  outputs:
    artifacts:
    - name: source
      path: /workspace
  container:
    image: alpine:3.19
    command: [sh, -c]
    args: ["echo data > /workspace/file.txt"]
```

```yaml
- name: consumer
  inputs:
    artifacts:
    - name: source
      path: /workspace
  container:
    image: alpine:3.19
    command: [cat, /workspace/file.txt]
```

**Artifact repositories:** S3, GCS, Azure Blob, HDFS, OSS. Configure once, use in many workflows.

```yaml
# artifact-repo-configmap
data:
  artifactRepository: |
    s3:
      bucket: my-bucket
      keyPrefix: workflows/
      endpoint: minio.example.com
      insecure: true
      accessKeySecret:
        name: my-secret
        key: accessKey
      secretKeySecret:
        name: my-secret
        key: secretKey
```

## Loops

```yaml
- name: process-items
  inputs:
    parameters:
    - name: items
      value: "item1,item2,item3"
  steps:
  - - name: process
      template: process-one
      arguments:
        parameters:
        - name: item
          value: "{{item}}"
      withItems:
      - item1
      - item2
      - item3
```

Or with a JSON list:

```yaml
withItems:
- { x: "1", y: "2" }
- { x: "3", y: "4" }
```

**withSequence** for ranges:

```yaml
withSequence:
  count: 10
```

**withParam** for runtime lists:

```yaml
arguments:
  parameters:
  - name: items
    value: |
      ["item1", "item2", "item3"]
```

## Retries and timeouts

```yaml
- name: flaky-step
  retryStrategy:
    limit: 3
    backoff:
      duration: "10s"
      factor: 2
      maxDuration: "5m"
  container:
    image: myapp:v1
    command: [sh, -c]
    args: ["flaky-command"]
```

```yaml
- name: long-running
  activeDeadlineSeconds: 3600   # timeout
  container:
    image: myapp:v1
    command: [sh, -c]
    args: ["long-command"]
```

## Cron workflows

```yaml
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: nightly-backup
spec:
  schedule: "0 2 * * *"
  timezone: "America/Los_Angeles"
  concurrencyPolicy: "Replace"  # Forbid, Replace, Allow
  startingDeadlineSeconds: 0
  
  workflowSpec:
    entrypoint: backup
    templates:
    - name: backup
      container:
        image: backup:latest
        command: [sh, -c]
        args: ["./backup.sh"]
```

**Concurrency policies:**
- `Allow` — multiple runs OK
- `Forbid` — skip if previous is running
- `Replace` — cancel previous, start new

## Workflow of Workflows (WoW)

For complex orchestration:

```yaml
- name: submit-child
  steps:
  - - name: trigger
      template: submit
      arguments:
        parameters:
        - name: workflow-name
          value: child-workflow

- name: submit
  resource:
    action: create
    manifest: |
      apiVersion: argoproj.io/v1alpha1
      kind: Workflow
      metadata:
        generateName: child-
      spec:
        workflowTemplateRef:
          name: child-template
```

Or use `workflowTemplateRef` to reference a reusable template.

## Workflow templates (reusable)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: build-and-push
  namespace: argo
spec:
  templates:
  - name: build-and-push
    inputs:
      parameters:
      - name: repo
      - name: tag
    container:
      image: gcr.io/kaniko-project/executor:debug
      command: [sh, -c]
      args:
      - /kaniko/executor --context=$REPO --destination=myregistry/myapp:$TAG
      env:
      - name: REPO
        value: "{{inputs.parameters.repo}}"
      - name: TAG
        value: "{{inputs.parameters.tag}}"
```

```bash
argo submit --from workflowtemplate/build-and-push \
  -p repo=https://github.com/myorg/myapp \
  -p tag=v1.2.3
```

## ClusterWorkflowTemplates (cluster-scoped)

Same as WorkflowTemplate, but available to all namespaces.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ClusterWorkflowTemplate
metadata:
  name: shared-build
spec:
  templates:
  - name: build
    container:
      image: alpine:3.19
      command: [sh, -c]
      args: ["echo shared"]
```

## The Argo Events integration

Argo Workflows + Argo Events = event-driven workflows.

```
GitHub push → EventSource → Sensor → Workflow submit
                                          ↓
                                    workflow runs
```

**Use case:** trigger CI on every PR push.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: ci-sensor
spec:
  template:
    serviceAccountName: operate-workflow-sa
  dependencies:
  - name: github-event
    eventSourceName: github
    eventName: push
    filters:
      data:
      - path: body.ref
        type: string
        comparator: "="
        value:
        - "refs/heads/main"
  triggers:
  - template:
      name: run-ci
      k8s:
        group: argoproj.io
        version: v1alpha1
        resource: workflows
        operation: create
        parameters:
        - src:
            dependencyName: github-event
            dataKey: body.head_commit.id
          dest: metadata.labels.commit-id
```

## Workflow status and UI

### CLI

```bash
argo list -n argo                      # list workflows
argo get <name> -n argo                # details
argo logs <name> -n argo               # logs
argo logs <name> -c main -n argo       # main container logs
argo logs <name> --since 1h -n argo    # recent logs
argo terminate <name> -n argo          # kill
argo retry <name> -n argo              # retry
argo delete <name> -n argo             # delete
argo watch <name> -n argo              # watch progress
```

### Web UI

```bash
argo server -n argo
# exposes UI on :2746
```

UI shows: workflow DAG, step status, logs, artifacts, retry, terminate.

## Service accounts and RBAC

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-workflow-sa
  namespace: argo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: workflow-runner
  namespace: my-app
rules:
- apiGroups: [""]
  resources: ["pods", "configmaps", "secrets"]
  verbs: ["get", "list", "create", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: workflow-runner
  namespace: my-app
subjects:
- kind: ServiceAccount
  name: argo-workflow-sa
  namespace: argo
roleRef:
  kind: Role
  name: workflow-runner
  apiGroup: rbac.authorization.k8s.io
```

Workflow pods use this SA. They can create resources in `my-app` namespace.

**For pushing to ECR:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-workflow-sa
  namespace: argo
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::xxx:role/argo-workflow-role
```

See [[Kubernetes/guides/non-functional/oidc-integration|oidc-integration]] for cloud workload identity.

## Common gotchas

* **Each step is a pod.** Pulling 50 large images is slow. Use a small base image.
* **EmptyDir volumes are per-pod.** Use artifact repositories for cross-step data.
* **`workflow.status` is not in the manifest.** You can only see it via `argo get` or the UI.
* **CronWorkflow timezone** must be set explicitly, otherwise UTC.
* **Retries count against the workflow's overall deadline.** Set `activeDeadlineSeconds` high enough.
* **`generateName` makes names unique.** If you need a stable name, use `name`.
* **The `argo` namespace must exist** before installing.
* **Garbage collection** is on by default; completed workflows are deleted. Set `ttlSecondsAfterFinished`.
* **Resource limits** in container template apply to the step pod. Set sensible defaults.
* **Service account permissions** are critical. The workflow pod uses the SA, not the submitter's.
* **Parallel steps with shared resources** can race. Use mutexes (`synchronization`).
* **Suspend templates** wait for `argo resume` or timeout. Don't suspend forever in production.
* **Workflow of Workflows** is powerful but complex. Prefer templates and reuse over deep nesting.

## Performance tips

* **Use a small base image.** Every step is a pod; pulling 1GB per step is slow.
* **Cache images on nodes.** Use DaemonSet-based registry mirrors.
* **Use pod garbage collection** to clean up completed pods.
* **Use WorkflowTemplate** for reusability — same image, less cold start.
* **Set resource requests/limits** so the scheduler can place pods efficiently.
* **Use `withItems`** for parallelism, not sequential loops.
* **Set `parallelism`** to limit concurrent pods.
* **Use emptyDir for cross-step data** within a single workflow, not artifacts.

## A worked CI/CD pipeline

**Goal:** on push to main, run tests, build image, scan, push, deploy to dev via GitOps.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: ci-pipeline
  namespace: argo
spec:
  entrypoint: pipeline
  serviceAccountName: ci-workflow-sa
  
  templates:
  - name: pipeline
    inputs:
      parameters:
      - name: repo-url
      - name: branch
        value: "main"
      - name: image-tag
    dag:
      tasks:
      - name: checkout
        template: checkout
        arguments:
          parameters:
          - {name: repo-url, value: "{{inputs.parameters.repo-url}}"}
          - {name: branch, value: "{{inputs.parameters.branch}}"}
      
      - name: test
        dependencies: [checkout]
        template: test
        arguments:
          parameters:
          - {name: tag, value: "{{inputs.parameters.image-tag}}"}
      
      - name: build
        dependencies: [test]
        template: build
        arguments:
          parameters:
          - {name: tag, value: "{{inputs.parameters.image-tag}}"}
      
      - name: scan
        dependencies: [build]
        template: scan
        arguments:
          parameters:
          - {name: tag, value: "{{inputs.parameters.image-tag}}"}
      
      - name: update-gitops
        dependencies: [scan]
        template: update-gitops
        arguments:
          parameters:
          - {name: tag, value: "{{inputs.parameters.image-tag}}"}
  
  - name: checkout
    # ... as before
  - name: test
    # ... as before
  - name: build
    # ... as before
  - name: scan
    # ... as before
  
  - name: update-gitops
    container:
      image: alpine/git:v2.42.0
      workingDir: /workspace
      command: [sh, -c]
      args:
      - |
        set -e
        git clone https://oauth2:$GITOPS_TOKEN@github.com/myorg/gitops-repo.git
        cd gitops-repo
        git config user.email "ci@example.com"
        git config user.name "CI Bot"
        # use kustomize to update the image tag
        cd overlays/dev
        kustomize edit set image myregistry/myapp=myregistry/myapp:$IMAGE_TAG
        git commit -am "ci: bump myapp to $IMAGE_TAG"
        git push
      env:
      - name: GITOPS_TOKEN
        valueFrom:
          secretKeyRef:
            name: gitops-token
            key: token
      - name: IMAGE_TAG
        value: "{{inputs.parameters.tag}}"
```

**Triggered by Argo Events on push to main.**

## See also

* [[Kubernetes/guides/delivery/gitops/basics|gitops-basics]] — what Argo Workflows deploys to
* [[Kubernetes/guides/delivery/templating-patching/helm/cicd|helm-cicd]] — Helm in pipelines
* [[Kubernetes/guides/delivery/pipeline-workflows/tekton-pipelines|tekton-pipelines]] — alternative
* [Argo Workflows docs](https://argoproj.github.io/argo-workflows/)
