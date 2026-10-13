---
title: "Lab CKS-07 — Image Scanning & Static Analysis"
tags: [kubernetes, labs, cks, trivy, sbom, kubesec, kube-linter, supply-chain]
date: 2026-10-13
description: "Scan images for vulnerabilities with Trivy, generate and query an SBOM, statically analyse manifests and Dockerfiles with kubesec, KubeLinter and Trivy, and verify a release binary by checksum."
---

# Lab CKS-07 — Image Scanning & Static Analysis

Supply chain security is 20% of the CKS, and most of it is running a scanner and acting on the result. This lab covers the four tools the objectives point at, plus checksum verification of platform binaries from the Cluster Setup domain.

Concepts: [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image Hardening]], [[Kubernetes/concepts/L07-security/04-admission-policy/23-sboms|SBOMs]] and [[Security/kubernetes-security/vulnerability-scanning/README|Vulnerability Scanning]].

Tested on kind v0.31 with Kubernetes v1.35.0 (the version the CKS exam used on 2026-10-13). Not re-run on v1.37; expect small differences in output there.

Verified with Trivy 0.70, kubesec v2 and KubeLinter 0.8.3. Vulnerability counts change daily as databases update, so your numbers will differ from the ones shown.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**.
- Trivy installed locally, and Docker to run kubesec and KubeLinter from their images. In the exam the tools are already on the node.

```bash
mkdir scan-lab && cd scan-lab
kubectl create namespace scan-lab
kubectl -n scan-lab run old --image=nginx:1.19
kubectl -n scan-lab run current --image=nginxinc/nginx-unprivileged:1.28-alpine
```

---

## 2. Scan Images with Trivy

```bash
trivy image nginx:1.19
trivy image --severity HIGH,CRITICAL nginx:1.19
trivy image --severity CRITICAL --quiet --format json nginx:1.19 \
  | jq '[.Results[].Vulnerabilities[]?] | length'
```

| Flag               | Use                                                     |
| :----------------- | :------------------------------------------------------ |
| `--severity`       | Filter by `UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL`            |
| `--ignore-unfixed` | Hide vulnerabilities with no fixed version yet          |
| `--format json`    | Machine-readable output for `jq`                        |
| `--exit-code 1`    | Fail the command when something is found, for pipelines |
| `--quiet`          | Suppress progress output                                |

### The exam task: scan what is running and remove the worst

List the images in use, scan each, and act on the result:

```bash
kubectl -n scan-lab get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

for img in $(kubectl -n scan-lab get pods -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u); do
  n=$(trivy image --severity CRITICAL --quiet --format json "$img" | jq '[.Results[].Vulnerabilities[]?] | length')
  echo "$n CRITICAL  $img"
done
```

```text
42 CRITICAL  nginx:1.19
3 CRITICAL  nginxinc/nginx-unprivileged:1.28-alpine
```

Even a current image is rarely at zero. Here the old image is the clear outlier, so remove the Pod that runs it:

```bash
kubectl -n scan-lab delete pod old
```

Read the task wording carefully. "Delete Pods with CRITICAL vulnerabilities" and "delete Pods with HIGH or CRITICAL vulnerabilities" give different answers, and so does a task that names one specific CVE.

---

## 3. Software Bill of Materials

An SBOM lists every package in an image. It answers "are we affected by this CVE?" without rescanning or even pulling the image.

```bash
trivy image --quiet --format spdx-json -o nginx.spdx.json nginx:alpine
trivy image --quiet --format cyclonedx -o nginx.cdx.json nginx:alpine
```

Query them for a package:

```bash
jq -r '.packages[] | select(.name | test("^lib(ssl|crypto)")) | "\(.name) \(.versionInfo)"' nginx.spdx.json | sort -u
jq -r '.components[] | select(.name=="busybox") | "\(.name) \(.version)"' nginx.cdx.json
jq '.components | length' nginx.cdx.json
```

Scan the SBOM itself instead of the image:

```bash
trivy sbom --severity HIGH,CRITICAL nginx.cdx.json
```

| Format    | Trivy `--format` | Key to query in `jq`                       |
| :-------- | :--------------- | :----------------------------------------- |
| SPDX      | `spdx-json`      | `.packages[]` with `.name`, `.versionInfo` |
| CycloneDX | `cyclonedx`      | `.components[]` with `.name`, `.version`   |

The exam may provide `bom` or `syft` for generation. The output formats are the same two, so the `jq` queries carry over.

---

## 4. Static Analysis of Manifests

Start with a manifest that has obvious problems:

```bash
cat > risky.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: risky
spec:
  containers:
    - name: app
      image: nginx
      securityContext:
        privileged: true
EOF
```

### kubesec

kubesec scores a manifest. Critical findings subtract points and each hardening setting adds some:

```bash
docker run --rm -i kubesec/kubesec:v2 scan /dev/stdin < risky.yaml \
  | jq -r '.[0] | "score=\(.score)  \(.message)",
                  (.scoring.critical[]? | "CRITICAL  \(.id)  \(.reason)"),
                  (.scoring.advise[0:4][]? | "ADVISE    \(.id)  +\(.points)")'
```

```text
score=-30  Failed with a score of -30 points
CRITICAL  Privileged  Privileged containers can allow almost completely unrestricted host access
ADVISE    ApparmorAny  +3
ADVISE    ServiceAccountName  +3
...
```

With the binary installed, the command is `kubesec scan risky.yaml`.

### KubeLinter

KubeLinter reports each failed check with a remediation:

```bash
docker run --rm -v "$PWD":/w:ro stackrox/kube-linter:latest lint /w/risky.yaml
```

It reports seven errors for this file: `privileged-container`, `privilege-escalation-container`, `run-as-non-root`, `no-read-only-root-fs`, `latest-tag`, `unset-cpu-requirements` and `unset-memory-requirements`.

### Fix and rescan

```bash
cat > fixed.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: risky
spec:
  containers:
    - name: app
      image: nginxinc/nginx-unprivileged:1.28-alpine
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
      resources:
        requests: { cpu: 50m, memory: 64Mi }
        limits: { cpu: 200m, memory: 128Mi }
EOF

docker run --rm -i kubesec/kubesec:v2 scan /dev/stdin < fixed.yaml | jq -r '.[0] | "score=\(.score)  \(.message)"'
docker run --rm -v "$PWD":/w:ro stackrox/kube-linter:latest lint /w/fixed.yaml
```

kubesec now passes with a positive score and KubeLinter reports `No lint errors found!`.

A manifest that passes a linter is not automatically runnable. This one sets a read-only root filesystem, and nginx needs to write under `/tmp`, so it also needs the `emptyDir` from [[Kubernetes/labs/cks/05-seccomp-apparmor-and-immutability|Lab CKS-05]].

---

## 5. Static Analysis of Dockerfiles

Trivy also checks configuration files, including Dockerfiles and Kubernetes manifests:

```bash
cat > Dockerfile <<'EOF'
FROM ubuntu:latest
RUN apt-get update && apt-get install -y curl
COPY app.sh /app.sh
ENV API_TOKEN=abc123
CMD ["/app.sh"]
EOF

trivy config .
trivy config risky.yaml
```

The Dockerfile scan reports five findings: the untagged-or-`latest` base image (`DS-0001`), no non-root `USER` (`DS-0002`), no `HEALTHCHECK` (`DS-0026`), `apt-get install` without `--no-install-recommends` (`DS-0029`) and a secret exposed in `ENV` (`DS-0031`).

An exam task may give you a Dockerfile and no scanner, so learn to spot the same problems by eye:

| Problem in a Dockerfile           | Fix                                                                       |
| :-------------------------------- | :------------------------------------------------------------------------ |
| `FROM image:latest` or no tag     | Pin a specific version, ideally by digest                                 |
| Large general-purpose base image  | A minimal or distroless base, and a multi-stage build                     |
| No `USER`, or `USER root`         | Create and switch to a non-root user                                      |
| Secrets in `ENV`, `ARG` or `COPY` | Remove them; supply at runtime from a Secret                              |
| `apt-get install` without cleanup | Install only what is needed and clear the package cache in the same layer |
| `ADD` with a URL                  | `COPY` a verified local file                                              |

---

## 6. Verify Platform Binaries

Before deploying a Kubernetes binary, compare its hash with the one published for the release:

```bash
V=v1.35.0
curl -fsSLO https://dl.k8s.io/release/$V/bin/linux/amd64/kubectl
curl -fsSL https://dl.k8s.io/release/$V/bin/linux/amd64/kubectl.sha512 -o kubectl.sha512
echo "$(cat kubectl.sha512)  kubectl" | sha512sum --check
```

```text
kubectl: OK
```

The same check works for a binary that is already installed. Compare what is on the node with what the release published:

```bash
docker exec k8s-lab-control-plane sha512sum /usr/bin/kubelet
curl -fsSL https://dl.k8s.io/release/$V/bin/linux/amd64/kubelet.sha512
```

Use the version the node actually runs, from `kubectl get nodes`. If the two hashes differ, the binary is not the released one. An exam task of this kind gives you several binaries and asks which one has been tampered with.

---

## 7. Controlled Failure Scenario: Two Scans, Two Answers

```bash
trivy image --severity CRITICAL --quiet --format json nginx:1.19 | jq '[.Results[].Vulnerabilities[]?] | length'
trivy image --severity CRITICAL --ignore-unfixed --quiet --format json nginx:1.19 | jq '[.Results[].Vulnerabilities[]?] | length'
```

```text
42
40
```

The same image gives two different counts. `--ignore-unfixed` hides every vulnerability the distribution has not published a fix for, which is useful for a to-do list and wrong for a risk assessment: an unfixed vulnerability is still exploitable.

Three ways a scan result misleads:

- **Different flags.** A task that says "count the CRITICAL vulnerabilities" is answered without `--ignore-unfixed` unless it says otherwise. Use exactly the severities it names.
- **Scanning a tag, not what runs.** `nginx:1.19` in a registry today may not be the bytes a Pod pulled last year. Compare the digest in `kubectl get pod -o jsonpath='{.status.containerStatuses[*].imageID}'`.
- **Scanning once.** An image that was clean at build time accumulates CVEs as they are published, which is why scanning belongs on a schedule and at admission as well as in the pipeline.

---

## 8. Cleanup

```bash
kubectl delete namespace scan-lab
cd .. && rm -rf scan-lab
```

---

## Further reading

- [Trivy documentation](https://trivy.dev/latest/docs/)
- [kubesec](https://kubesec.io/)
- [KubeLinter](https://docs.kubelinter.io/)
- [Download Kubernetes](https://kubernetes.io/releases/download/)

## Next Lab

Proceed to **[[Kubernetes/labs/cks/08-image-admission-control|Lab CKS-08 — Image Admission Control]]**, or return to the [[Kubernetes/certifications/cks|CKS Track]].
