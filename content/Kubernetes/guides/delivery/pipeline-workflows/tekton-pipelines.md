---
title: Tekton Pipelines
tags:
  - Kubernetes
  - Delivery
  - CI/CD
  - Tekton
---

Tekton is the **k8s-native CI/CD framework**. Where Argo Workflows is general-purpose, Tekton is purpose-built for CI/CD. Pipelines are made of `Task`s, `Pipeline`s, and `PipelineRun`s. Every step runs in a pod. You get triggers, workspaces, and a real k8s resource model.

## Tekton vs Argo Workflows

| | Tekton | Argo Workflows |
|---|--------|---------------|
| **Purpose** | CI/CD | General workflows |
| **Model** | Tasks + Pipelines | Templates + DAGs |
| **Triggers** | Built-in (Tekton Triggers) | Separate (Argo Events) |
| **Result tracking** | PipelineResources (deprecated), OCI artifacts | Artifacts |
| **CLI** | `tkn` | `argo` |
| **UI** | Tekton Dashboard | Argo Workflows UI |
| **Ecosystem** | Tekton Hub (reusable tasks) | Templates |
| **Maturity** | GA in 2023 | Mature |

**For CI/CD specifically:** Tekton's model is more focused. For batch jobs, ML, etc., Argo Workflows is more flexible.

## The mental model

```
PipelineRun (a specific execution)
   │
   └── Pipeline (the template)
          │
          ├── Task 1 (clone)
          ├── Task 2 (test)        ← depends on Task 1
          ├── Task 3 (build)       ← depends on Task 2
          ├── Task 4 (scan)        ← depends on Task 3
          └── Task 5 (push)        ← depends on Task 4
                                       │
                                       └── Each Task runs Steps in containers
                                              │
                                              ├── Step 1 (git clone)
                                              ├── Step 2 (configure)
                                              └── Step 3 (run)
```

- **Task:** a unit of work (one or more steps)
- **Step:** a single command in a container
- **Pipeline:** a DAG of Tasks
- **PipelineRun:** an execution of a Pipeline

## A simple CI pipeline

```yaml
# Task: git-clone
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: git-clone
spec:
  params:
  - name: url
  - name: revision
    default: main
  workspaces:
  - name: output
  steps:
  - name: clone
    image: alpine/git:v2.42.0
    script: |
      git clone $(params.url) $(workspaces.output.path)
      cd $(workspaces.output.path)
      git checkout $(params.revision)
```

```yaml
# Task: build-and-push
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: build-and-push
spec:
  params:
  - name: IMAGE
  - name: TAG
  workspaces:
  - name: source
  steps:
  - name: build
    image: gcr.io/kaniko-project/executor:debug
    workingDir: $(workspaces.source.path)
    script: |
      /kaniko/executor \
        --context=$(workspaces.source.path) \
        --dockerfile=$(workspaces.source.path)/Dockerfile \
        --destination=$(params.IMAGE):$(params.TAG) \
        --cache=true
```

```yaml
# Pipeline
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: build-and-deploy
spec:
  params:
  - name: git-url
  - name: image-name
  - name: image-tag
  workspaces:
  - name: shared
  tasks:
  - name: clone
    taskRef:
      name: git-clone
    params:
    - name: url
      value: $(params.git-url)
    workspaces:
    - name: output
      workspace: shared

  - name: test
    runAfter: [clone]
    taskSpec:
      workspaces:
      - name: source
      steps:
      - name: test
        image: golang:1.21
        workingDir: $(workspaces.source.path)
        script: |
          go test ./...
    workspaces:
    - name: source
      workspace: shared

  - name: build
    runAfter: [test]
    taskRef:
      name: build-and-push
    params:
    - name: IMAGE
      value: $(params.image-name)
    - name: TAG
      value: $(params.image-tag)
    workspaces:
    - name: source
      workspace: shared
```

```yaml
# PipelineRun
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: build-myapp-
spec:
  pipelineRef:
    name: build-and-deploy
  params:
  - name: git-url
    value: https://github.com/myorg/myapp
  - name: image-name
    value: myregistry/myapp
  - name: image-tag
    value: v1.2.3
  workspaces:
  - name: shared
    volumeClaimTemplate:
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 5Gi
```

**Run:**

```bash
kubectl apply -f pipelinerun.yaml
```

## Tasks and Steps

### Task

A Task is a **reusable template**. The Pod is created with one container per Step.

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: my-task
spec:
  params:
  - name: image-name
    type: string
    default: myapp
  workspaces:
  - name: source
  results:
  - name: image-digest
    description: The digest of the built image
  steps:
  - name: build
    image: gcr.io/kaniko-project/executor:debug
    script: |
      /kaniko/executor ...
  - name: report
    image: alpine:3.19
    script: |
      echo "$(steps.build.results.digest)" > $(results.image-digest.path)
```

**Task can be inline** (`taskSpec:`) or **referenced** (`taskRef: { name: ... }`).

### Steps

Steps are commands in containers. They run sequentially in the same Pod.

```yaml
steps:
- name: install
  image: golang:1.21
  script: go mod download

- name: test
  image: golang:1.21
  script: go test ./...

- name: build
  image: gcr.io/kaniko-project/executor:debug
  script: /kaniko/executor ...
```

Each Step:
- Runs in its own container
- Can have its own image
- Has its own working dir
- Can mount workspaces

## Workspaces

Workspaces are shared volumes between Tasks.

```yaml
# Task definition
spec:
  workspaces:
  - name: source
    description: Source code
    mountPath: /workspace

# Pipeline definition
spec:
  workspaces:
  - name: shared
    description: Shared workspace

  tasks:
  - name: clone
    taskRef: { name: git-clone }
    workspaces:
    - name: output
      workspace: shared

  - name: test
    runAfter: [clone]
    taskRef: { name: run-tests }
    workspaces:
    - name: source
      workspace: shared

# PipelineRun
spec:
  workspaces:
  - name: shared
    volumeClaimTemplate:
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 5Gi
```

**Types of workspaces:**
- **EmptyDir** — fast, ephemeral (default in some configs)
- **PersistentVolumeClaim** — persistent across runs
- **ConfigMap / Secret** — for config
- **Existing PVC** — for sharing with other k8s resources

## Parameters

```yaml
# Task
spec:
  params:
  - name: image-tag
    type: string
    description: The image tag
  steps:
  - name: build
    image: alpine:3.19
    args: ["build", "$(params.image-tag)"]
```

```yaml
# Pipeline
spec:
  params:
  - name: image-tag
  tasks:
  - name: build
    taskRef: { name: build }
    params:
    - name: image-tag
      value: $(params.image-tag)
```

```yaml
# PipelineRun
spec:
  params:
  - name: image-tag
    value: "v1.2.3"
```

**Parameter types:** string, array, object.

## Results

Tasks can output results that other Tasks consume.

```yaml
# Task: produce
spec:
  results:
  - name: commit-sha
  steps:
  - name: get-commit
    image: alpine/git:v2.42.0
    script: |
      git rev-parse HEAD > $(results.commit-sha.path)
```

```yaml
# Pipeline
spec:
  tasks:
  - name: get-commit
    taskRef: { name: produce }
  - name: use-commit
    runAfter: [get-commit]
    taskRef: { name: use }
    params:
    - name: sha
      value: "$(tasks.get-commit.results.commit-sha)"
```

## Tekton Triggers

Event-driven CI. Listens for events (GitHub push, GitLab, etc.) and creates PipelineRuns.

```yaml
# EventListener
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-listener
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: github-push
    interceptors:
    - ref:
        name: github
      params:
      - name: eventTypes
        value: [push]
    - ref:
        name: cel
      params:
      - name: filters
        value:
        - "body.ref=='refs/heads/main'"
    bindings:
    - ref: github-push-binding
    template:
      ref: github-push-template
```

```yaml
# TriggerTemplate
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-push-template
spec:
  params:
  - name: gitrevision
  - name: gitrepositoryurl
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: ci-push-
    spec:
      pipelineRef:
        name: build-and-deploy
      params:
      - name: git-url
        value: $(tt.params.gitrepositoryurl)
      - name: image-tag
        value: $(tt.params.gitrevision)
```

The EventListener exposes an HTTP endpoint. Configure GitHub webhook to point to it.

## Tekton Hub (reusable tasks)

The community-maintained catalog of Tasks:

```bash
# install the tkn CLI
brew install tektoncd-cli

# install a task from the hub
tkn hub install task git-clone
tkn hub install task buildah
tkn hub install task knative-deploy
```

Reusable Tasks for common operations (git, buildah, kaniko, s3, etc.).

## Auth: Service Accounts and Secrets

Tekton Tasks need credentials for git, registries, etc.

```yaml
# Secret for registry
apiVersion: v1
kind: Secret
metadata:
  name: registry-creds
  namespace: tekton-pipelines
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64-of-dockerconfig>
---
# ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ci-sa
  namespace: tekton-pipelines
secrets:
- name: registry-creds
```

```yaml
# Task
spec:
  steps:
  - name: push
    image: buildah
    script: buildah push ...
    # service account auto-mounts the secret
```

For cloud registries, use workload identity (AWS IRSA, GKE WI).

## Tekton vs Jenkins (brief)

| | Tekton | Jenkins |
|---|--------|---------|
| **Architecture** | k8s-native, declarative | Master + agents |
| **State** | None (in k8s) | Heavy (Jenkins home) |
| **Plugins** | Tasks (k8s resources) | Many plugins, fragile |
| **UI** | Tekton Dashboard | Jenkins UI |
| **GitOps-friendly** | Yes (CRDs in git) | Hard (XML/JCasC) |
| **Scale** | Pods scale, no master bottleneck | Master bottleneck |
| **Maturity** | 2020+ | 2010s+ |

**Use Tekton:** for new k8s-native CI/CD, especially if you're already GitOps-pilled.

**Use Jenkins:** if you have an existing investment, legacy pipelines, or need plugins Tekton doesn't have.

## Common gotchas

* **Steps run sequentially in one pod.** If you need parallelism, use multiple Tasks.
* **Workspaces are mounted in each Task pod.** Make sure the Task spec mounts them.
* **Results are passed via files.** A Task writes to a path, another Task reads.
* **Service account permissions are key.** Tekton Tasks run as the SA, not the user.
* **Triggers require interceptors** to filter events. Without them, every push triggers a run.
* **Hub tasks are versioned.** Pin a specific version, not "latest."
* **PipelineRun timeout** is set per-PipelineRun, not on the Pipeline.
* **Retries** are set per-Task, not per-Pipeline.
* **Workspaces can't be shared across PipelineRuns** unless you use a PVC.
* **Triggers use CEL** for filtering (or interceptors), which is its own learning curve.

## A worked CI/CD pipeline

**Goal:** GitHub push to main → clone → test → build → scan → push → update gitops.

```yaml
# Pipeline
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: ci
spec:
  params:
  - name: git-url
  - name: git-revision
  - name: image-name
  - name: image-tag
  workspaces:
  - name: shared
  tasks:
  - name: clone
    taskRef: { name: git-clone }
    workspaces:
    - name: output
      workspace: shared
    params:
    - name: url
      value: $(params.git-url)
    - name: revision
      value: $(params.git-revision)

  - name: test
    runAfter: [clone]
    taskRef: { name: golang-test }
    workspaces:
    - name: source
      workspace: shared

  - name: build
    runAfter: [test]
    taskRef: { name: kaniko }
    workspaces:
    - name: source
      workspace: shared
    params:
    - name: IMAGE
      value: $(params.image-name)
    - name: TAG
      value: $(params.image-tag)

  - name: scan
    runAfter: [build]
    taskRef: { name: trivy-scanner }
    params:
    - name: IMAGE
      value: $(params.image-name):$(params.image-tag)

  - name: update-gitops
    runAfter: [scan]
    taskRef: { name: update-kustomize }
    params:
    - name: repo
      value: https://github.com/myorg/gitops
    - name: image-tag
      value: $(params.image-tag)
```

The `update-gitops` task uses `kustomize edit set image` to update the manifest and pushes to the gitops repo.

## See also

* [[Kubernetes/guides/delivery/pipeline-workflows/argo-workflows|argo-workflows]] — alternative
* [[Kubernetes/guides/delivery/gitops/basics|gitops-basics]] — what Tekton deploys to
* [[Kubernetes/guides/delivery/templating-patching/kustomize|kustomize]] — image updates
* [Tekton docs](https://tekton.dev/docs/)
