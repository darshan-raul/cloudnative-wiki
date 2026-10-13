---
title: "Lab CKS-09 — Image Signing with cosign"
tags: [kubernetes, labs, cks, cosign, sigstore, supply-chain, image-signing]
date: 2026-10-13
description: "Sign an image by digest with cosign, verify it with the public key, detect a tag that was overwritten with unsigned content, and require digest references at admission."
---

# Lab CKS-09 — Image Signing with cosign

A scan says what is inside an image. A signature says who produced it and that it has not changed since. This lab signs an image with a key pair, verifies it, and shows why a signature is only meaningful when the cluster runs images by digest.

Concepts: [[Kubernetes/concepts/L07-security/04-admission-policy/23-sboms|SBOMs]] (which covers cosign and attestations), [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image Hardening]] and [[Containers/registries|Registries]].

Tested on kind v0.31 with Kubernetes v1.35.0 (the version the CKS exam used on 2026-10-13). Not re-run on v1.37; expect small differences in output there. This lab creates its own cluster and a local registry, and needs more memory than the other labs.

Verified on `kind` v0.31 with Kubernetes v1.35.0 and cosign v3.1.3.

---

## 1. Prerequisites & Starting State

- Docker, and `cosign` installed from the [Sigstore releases](https://github.com/sigstore/cosign/releases).
- A `kind` cluster that can pull from a local registry. Signatures are stored in a registry next to the image, so an image loaded with `kind load` cannot be signed.

### A cluster with a local registry

```bash
docker run -d -p 127.0.0.1:5001:5000 --name lab-registry registry:2

cat > kind-registry.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: sign-lab
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"
nodes:
  - role: control-plane
  - role: worker
EOF
kind create cluster --config kind-registry.yaml
docker network connect kind lab-registry

for node in $(kind get nodes --name sign-lab); do
  docker exec "$node" sh -c 'mkdir -p /etc/containerd/certs.d/localhost:5001 &&
    printf "[host.\"http://lab-registry:5000\"]\n" > /etc/containerd/certs.d/localhost:5001/hosts.toml'
done
```

Your machine reaches the registry as `localhost:5001`. The last loop tells each node that the same name maps to the registry container, so one image reference works in both places.

This lab uses its own cluster so the registry wiring does not disturb `k8s-lab`.

---

## 2. Build and Push Two Images

```bash
mkdir hello && cd hello
printf 'FROM nginxinc/nginx-unprivileged:1.28-alpine\nCOPY index.html /usr/share/nginx/html/index.html\n' > Dockerfile

printf '<h1>signed</h1>\n' > index.html
docker build -t localhost:5001/hello-web:1.0 . && docker push localhost:5001/hello-web:1.0

printf '<h1>unsigned</h1>\n' > index.html
docker build -t localhost:5001/hello-web:2.0 . && docker push localhost:5001/hello-web:2.0
cd ..
```

Record the digest of the first image. Everything from here on refers to it:

```bash
DIGEST=$(docker inspect --format '{{index .RepoDigests 0}}' localhost:5001/hello-web:1.0)
echo $DIGEST
```

```text
localhost:5001/hello-web@sha256:26bf0bb3bd88996f61d93f1de23d35e7508cd7d91d9d09509b987f42f6ee510f
```

A tag is a name that can be moved. A digest is a hash of the image manifest and identifies exactly one image.

---

## 3. Generate a Key Pair and Sign

```bash
COSIGN_PASSWORD="" cosign generate-key-pair
ls cosign.key cosign.pub
```

The private key signs and stays secret. The public key verifies and is handed to anyone who needs to check.

```bash
COSIGN_PASSWORD="" cosign sign --key cosign.key \
  --use-signing-config=false --tlog-upload=false --yes $DIGEST
```

```text
Signing artifact...
Pushing signature to: localhost:5001/hello-web
```

The two extra flags keep the signature out of the public Sigstore transparency log, which a lab registry on `localhost` has no business writing to. Signing a public image for real, you would leave the defaults on.

Always sign the digest. cosign warns if you give it a tag, because the tag might point somewhere else by the time the signature is pushed.

### Where the signature lives

```bash
cosign tree $DIGEST
curl -s localhost:5001/v2/hello-web/tags/list
```

```text
{"name":"hello-web","tags":["1.0","2.0","sha256-26bf0bb3...510f"]}
```

The signature is an ordinary artifact in the same repository, named after the digest it signs. Nothing in the image changed, and the registry needs no special support.

---

## 4. Verify

```bash
cosign verify --key cosign.pub --insecure-ignore-tlog $DIGEST
```

```text
Verification for localhost:5001/hello-web@sha256:26bf0bb3... --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The signatures were verified against the specified public key
```

`--insecure-ignore-tlog` matches the choice made when signing: there is no transparency log entry to check.

The unsigned image fails, with a non-zero exit code you can use in a script or pipeline:

```bash
cosign verify --key cosign.pub --insecure-ignore-tlog localhost:5001/hello-web:2.0; echo "exit=$?"
```

```text
Error: no signatures found
exit=10
```

A signature made with a different key fails too:

```bash
mkdir other && (cd other && COSIGN_PASSWORD="" cosign generate-key-pair)
cosign verify --key other/cosign.pub --insecure-ignore-tlog $DIGEST
```

```text
Error: no matching attestations: failed to verify signature: ...
```

"No signatures found" and "failed to verify signature" are different findings. The first means nobody signed the image. The second means somebody did, and it was not the key you trust.

---

## 5. Run Only What Was Verified

Verification is worthless if the cluster then pulls by tag, since the tag can change between the check and the pull. Deploy by digest, and make the cluster refuse anything else:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-image-digest
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: "object.spec.containers.all(c, c.image.contains('@sha256:'))"
      message: "images must be referenced by digest"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-image-digest
spec:
  policyName: require-image-digest
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchLabels:
        image-policy: digest-only
```

```bash
kubectl apply -f require-image-digest.yaml
kubectl create namespace sign-lab
kubectl label namespace sign-lab image-policy=digest-only

kubectl -n sign-lab run by-tag --image=localhost:5001/hello-web:1.0
kubectl -n sign-lab run by-digest --image=$DIGEST
kubectl -n sign-lab wait --for=condition=Ready pod/by-digest --timeout=90s
kubectl -n sign-lab exec by-digest -- cat /usr/share/nginx/html/index.html
```

```text
The pods "by-tag" is invalid: : ValidatingAdmissionPolicy 'require-image-digest' ... denied request: images must be referenced by digest
pod/by-digest created
<h1>signed</h1>
```

The pipeline step is then: build, push, sign the digest, verify the digest, deploy that digest.

> [!note] Verifying signatures at admission
> This policy enforces digests; it does not check the signature itself. Checking signatures inside the cluster needs a policy engine that can call the registry, such as a Kyverno `verifyImages` rule or the Sigstore policy controller. That step is not part of this lab. [[Kubernetes/concepts/L07-security/04-admission-policy/12-kyverno|Kyverno]] describes the approach.

---

## 6. Controlled Failure Scenario: A Tag That Moved

Verify by tag, which works today:

```bash
cosign verify --key cosign.pub --insecure-ignore-tlog localhost:5001/hello-web:1.0 > /dev/null; echo "exit=$?"
```

Now act as an attacker with push access, and overwrite the `1.0` tag with the unsigned image:

```bash
docker tag localhost:5001/hello-web:2.0 localhost:5001/hello-web:1.0
docker push localhost:5001/hello-web:1.0

cosign verify --key cosign.pub --insecure-ignore-tlog localhost:5001/hello-web:1.0
cosign verify --key cosign.pub --insecure-ignore-tlog $DIGEST > /dev/null; echo "digest exit=$?"
```

```text
Error: no signatures found
digest exit=0
```

The signature did its job: the swapped tag no longer verifies, and the original digest still does. Three things follow.

- A Deployment that referenced `hello-web:1.0` would have pulled the attacker's image on its next restart, and no signature check would have run unless something enforces one at admission.
- The Pod started in section 5 is unaffected. It was created by digest and will always get the signed image.
- Verifying a tag and then deploying that tag leaves a gap between the two steps. Verifying and deploying the same digest does not.

---

## 7. Cleanup

```bash
kind delete cluster --name sign-lab
kubectl config use-context kind-k8s-lab
docker rm -f lab-registry
docker image rm localhost:5001/hello-web:1.0 localhost:5001/hello-web:2.0
rm -rf hello other cosign.key cosign.pub kind-registry.yaml
```

---

## Further reading

- [Signing containers with cosign](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)
- [Verifying signatures](https://docs.sigstore.dev/cosign/verifying/verify/)
- [kind local registry](https://kind.sigs.k8s.io/docs/user/local-registry/)
- [Verify signed Kubernetes artifacts](https://kubernetes.io/docs/tasks/administer-cluster/verify-signed-artifacts/)

## Next Lab

Proceed to **[[Kubernetes/labs/cks/10-runtime-sandboxing-gvisor|Lab CKS-10 — Runtime Sandboxing with gVisor]]**, or return to the [[Kubernetes/certifications/cks|CKS Track]].
