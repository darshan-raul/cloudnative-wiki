---
title: "Lab CKAD-08 — Build & Ship Container Images"
tags: [kubernetes, labs, ckad, docker, images, dockerfile]
date: 2026-10-13
description: "Build, tag, modify, export and load a container image, then run it in the cluster, covering the CKAD objective on defining, building and modifying images."
---

# Lab CKAD-08 — Build & Ship Container Images

The CKAD objective "define, build and modify container images" is tested with small, mechanical tasks: build this Dockerfile with that tag, change one instruction, save the result to a file. This lab covers each of them.

Concepts: [[Containers/dockerfile-best-practices|Dockerfile Best Practices]], [[Containers/images-and-layers|Images and Layers]] and [[Containers/registries|Registries]].

Tested on kind v0.31 with Kubernetes v1.35.0. Not re-run on v1.37; the image build steps do not depend on the cluster version.

Verified with Docker 29 and `kind` v0.31. The exam may give you `docker` or `podman`; the subcommands used here are the same in both.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**.
- Docker or Podman on your machine.

```bash
mkdir hello-web && cd hello-web
kubectl create namespace image-lab
```

---

## 2. Build and Tag

```bash
printf '<h1>v1</h1>\n' > index.html

cat > Dockerfile <<'EOF'
FROM nginxinc/nginx-unprivileged:1.28-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
EOF

docker build -t hello-web:1.0 .
docker image ls hello-web
```

`-t name:tag` names the result and the final `.` is the build context, the directory whose files `COPY` can see. A Dockerfile with another name or location needs `-f`. The path below is an illustration of the syntax; this lab has no such file, so do not run it:

```text
docker build -t hello-web:1.0 -f build/Dockerfile.prod .
```

Add a second tag to the same image, for example to push it to a registry:

```bash
docker tag hello-web:1.0 registry.example.com/team/hello-web:1.0
docker image ls | grep hello-web
```

Both names show the same image ID. A tag is a pointer, not a copy.

---

## 3. Inspect

```bash
docker image inspect hello-web:1.0 --format '{{.Config.User}} {{.Config.ExposedPorts}} {{.Config.Cmd}}'
docker history hello-web:1.0
docker run --rm -d -p 8080:8080 --name hello hello-web:1.0
curl -s localhost:8080
docker rm -f hello
```

The image runs as user `101` and listens on `8080`, both inherited from the base image. Those two facts decide the `securityContext` and `containerPort` you write in the Pod manifest later.

---

## 4. Modify and Rebuild

Change the content and add a default environment variable, then build a new version:

```bash
printf '<h1>v2</h1>\n' > index.html

cat > Dockerfile <<'EOF'
FROM nginxinc/nginx-unprivileged:1.28-alpine
ENV APP_VERSION=2.0
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
EOF

docker build -t hello-web:2.0 .
docker run --rm hello-web:2.0 env | grep APP_VERSION
```

The instructions most often changed in a task:

| Instruction  | Sets                                                    | Pod field that overrides it                 |
| :----------- | :------------------------------------------------------ | :------------------------------------------ |
| `FROM`       | Base image                                              | None                                        |
| `ENTRYPOINT` | The executable                                          | `command`                                   |
| `CMD`        | Default arguments, or the executable if no `ENTRYPOINT` | `args`                                      |
| `ENV`        | Default environment variables                           | `env`                                       |
| `USER`       | User the process runs as                                | `securityContext.runAsUser`                 |
| `EXPOSE`     | Documentation of the listening port                     | None; `containerPort` is also documentation |
| `WORKDIR`    | Working directory                                       | `workingDir`                                |

---

## 5. Export and Import

Tasks often end with "store the image at this path":

```bash
docker save -o /tmp/hello-web-2.0.tar hello-web:2.0
ls -lh /tmp/hello-web-2.0.tar
tar -tf /tmp/hello-web-2.0.tar | head
```

The archive holds the layers plus an index. Load it back with:

```bash
docker image rm hello-web:2.0
docker load -i /tmp/hello-web-2.0.tar
```

With Podman, the task may name a format:

```bash
podman save --format oci-archive -o /tmp/hello-web-2.0.tar hello-web:2.0
```

`save` and `load` work on **images**. `export` and `import` work on a **container's filesystem** and lose the image metadata such as `CMD` and `ENV`. Use `save` unless a task says otherwise.

---

## 6. Run It in the Cluster

A `kind` cluster cannot see images in your local Docker daemon. Load them onto the nodes:

```bash
kind load docker-image hello-web:1.0 hello-web:2.0 --name k8s-lab
```

```bash
kubectl -n image-lab create deployment hello --image=hello-web:1.0 --port=8080
kubectl -n image-lab rollout status deployment/hello
kubectl -n image-lab port-forward deployment/hello 8080:8080 >/dev/null &
PF_PID=$!
curl -s --retry 5 --retry-connrefused localhost:8080
kill $PF_PID
```

Roll to the modified image:

```bash
kubectl -n image-lab set image deployment/hello hello-web=hello-web:2.0
kubectl -n image-lab rollout status deployment/hello
kubectl -n image-lab exec deployment/hello -- env | grep APP_VERSION
```

---

## 7. Controlled Failure Scenario: The Image That Exists but Cannot Be Pulled

```bash
docker tag hello-web:2.0 hello-web:latest
kind load docker-image hello-web:latest --name k8s-lab
kubectl -n image-lab create deployment broken --image=hello-web:latest
kubectl -n image-lab get pods -l app=broken
kubectl -n image-lab describe pod -l app=broken | tail -6
```

The Pod is in `ErrImagePull` or `ImagePullBackOff`, although the image is on every node. The events show the kubelet trying to pull `docker.io/library/hello-web:latest`.

The cause is the default pull policy. For the `latest` tag, or no tag at all, `imagePullPolicy` defaults to `Always`, so the kubelet ignores the local copy and asks a registry that has never heard of the image. Any other tag defaults to `IfNotPresent`.

```bash
kubectl -n image-lab patch deployment broken --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]'
kubectl -n image-lab get pods -l app=broken
```

The general playbook is in [[Kubernetes/guides/troubleshooting/image-pull|ImagePullBackOff]].

---

## 8. Cleanup

```bash
kubectl delete namespace image-lab
docker image rm hello-web:1.0 hello-web:2.0 hello-web:latest registry.example.com/team/hello-web:1.0
rm -f /tmp/hello-web-2.0.tar
```

Keep `hello-web:1.0` if you are going straight to the next lab, which uses it.

---

## Further reading

- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [docker image save](https://docs.docker.com/reference/cli/docker/image/save/)
- [Images](https://kubernetes.io/docs/concepts/containers/images/)

## Next Lab

Proceed to **[[Kubernetes/labs/ckad/09-ingress|Lab CKAD-09 — Ingress]]**, or return to the [[Kubernetes/certifications/ckad|CKAD Track]].
