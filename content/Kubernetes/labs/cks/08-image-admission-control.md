---
title: "Lab CKS-08 — Image Admission Control"
tags:
  [
    kubernetes,
    labs,
    cks,
    admission,
    imagepolicywebhook,
    validatingadmissionpolicy,
    supply-chain,
  ]
date: 2026-10-13
description: "Restrict which registries Pods may pull from with a ValidatingAdmissionPolicy, then configure the ImagePolicyWebhook admission plugin and observe its fail-closed behaviour."
---

# Lab CKS-08 — Image Admission Control

Scanning tells you an image is bad. Admission control stops it from running. This lab enforces "permitted registries" two ways: with a built-in ValidatingAdmissionPolicy, and with the ImagePolicyWebhook admission plugin that CKS tasks ask you to wire into the API server.

Concepts: [[Kubernetes/concepts/L07-security/04-admission-policy/10-admission-controllers|Admission Controllers]] and [[Kubernetes/concepts/L07-security/04-admission-policy/12-kyverno|Kyverno]] for the policy-engine alternative.

Tested on kind v0.31 with Kubernetes v1.35.0 (the version the CKS exam used on 2026-10-13). Not re-run on v1.37; expect small differences in output there.

Verified on `kind` v0.31 with Kubernetes v1.35.0.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**.
- A control plane node shell with an editor and a backup:

```bash
docker exec -it k8s-lab-control-plane bash
# node
apt-get update && apt-get install -y vim-tiny
mkdir -p /root/backup/cks-08 && cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/backup/cks-08/
```

---

## 2. Permitted Registries with a ValidatingAdmissionPolicy

A ValidatingAdmissionPolicy runs a CEL expression inside the API server. There is no webhook to deploy and nothing that can be unreachable.

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: trusted-registries
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: >-
        object.spec.containers.all(c,
          c.image.startsWith('registry.k8s.io/') ||
          c.image.startsWith('ghcr.io/stefanprodan/'))
      message: "images must come from registry.k8s.io or ghcr.io/stefanprodan"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: trusted-registries
spec:
  policyName: trusted-registries
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchLabels:
        registry-policy: enforced
```

The policy does nothing until a binding puts it into effect. This binding applies it only to namespaces carrying a label.

```bash
kubectl apply -f trusted-registries.yaml
kubectl create namespace vap-lab
kubectl label namespace vap-lab registry-policy=enforced

kubectl -n vap-lab run bad --image=nginx:alpine
kubectl -n vap-lab run good --image=registry.k8s.io/pause:3.10
```

```text
The pods "bad" is invalid: : ValidatingAdmissionPolicy 'trusted-registries' with binding 'trusted-registries' denied request: images must come from registry.k8s.io or ghcr.io/stefanprodan
pod/good created
```

Two gaps to close before relying on a rule like this:

- It checks `containers` only. `initContainers` and `ephemeralContainers` need the same expression.
- It matches Pods. A Deployment with a forbidden image is accepted and its ReplicaSet then fails to create Pods, which shows up in `kubectl describe replicaset`, not at `kubectl apply`.

Set `validationActions: ["Warn"]` or `["Audit"]` to roll a policy out without blocking anything first.

---

## 3. ImagePolicyWebhook

ImagePolicyWebhook is an admission plugin compiled into the API server. For every Pod it sends an `ImageReview` to an external service and admits or rejects on the answer. The backend is given in an exam task; your job is the four pieces of configuration.

### Step 1: Admission configuration

```bash
# node
mkdir -p /etc/kubernetes/admission

cat > /etc/kubernetes/admission/admission-config.yaml <<'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: ImagePolicyWebhook
    configuration:
      imagePolicy:
        kubeConfigFile: /etc/kubernetes/admission/imagepolicy.kubeconfig
        allowTTL: 50
        denyTTL: 50
        retryBackoff: 500
        defaultAllow: false
EOF
```

`defaultAllow` decides what happens when the backend cannot be reached. `false` rejects every Pod (fail closed); `true` admits every Pod (fail open). Tasks typically ask for `false`.

### Step 2: kubeconfig for the backend

Despite the name, this file describes how the API server reaches the **webhook**, not the cluster:

```bash
# node
cat > /etc/kubernetes/admission/imagepolicy.kubeconfig <<'EOF'
apiVersion: v1
kind: Config
clusters:
  - name: image-policy
    cluster:
      server: https://127.0.0.1:8443/image-policy
      certificate-authority: /etc/kubernetes/pki/ca.crt
users:
  - name: api-server
    user:
      client-certificate: /etc/kubernetes/pki/apiserver.crt
      client-key: /etc/kubernetes/pki/apiserver.key
contexts:
  - name: default
    context:
      cluster: image-policy
      user: api-server
current-context: default
EOF
```

Nothing listens on `127.0.0.1:8443` in this lab. That is deliberate: it lets you see exactly what `defaultAllow` does.

### Step 3: API server flags and mount

Edit `/etc/kubernetes/manifests/kube-apiserver.yaml`.

**Flags.** Append to the existing plugin list; do not replace it:

```yaml
- --enable-admission-plugins=NodeRestriction,ImagePolicyWebhook
- --admission-control-config-file=/etc/kubernetes/admission/admission-config.yaml
```

**Volume mount:**

```yaml
- name: admission
  mountPath: /etc/kubernetes/admission
  readOnly: true
```

**Volume:**

```yaml
- name: admission
  hostPath:
    path: /etc/kubernetes/admission
    type: Directory
```

```bash
# node
watch crictl ps --name kube-apiserver
```

Every path in the two configuration files is read from **inside** the API server container. The certificates under `/etc/kubernetes/pki` are already mounted; the `admission` directory is not, which is why it needs the new volume.

---

## 4. Verification

```bash
# host
kubectl get nodes
kubectl run ipw-test --image=nginx:alpine
```

```text
Error from server (Forbidden): pods "ipw-test" is forbidden: Post "https://127.0.0.1:8443/image-policy?timeout=30s": dial tcp 127.0.0.1:8443: connect: connection refused
```

The API server tried to ask the backend, could not, and rejected the Pod because `defaultAllow` is `false`. That shows the plugin is enabled, reads its configuration and fails closed. It does **not** show that the TLS settings in the kubeconfig are right, that an `ImageReview` request is well formed, or that a backend would allow one image and deny another; this lab has no backend to prove those.

Now flip the default and restart the API server so it rereads the file:

```bash
# node
sed -i 's/defaultAllow: false/defaultAllow: true/' /etc/kubernetes/admission/admission-config.yaml
crictl stop $(crictl ps -q --name kube-apiserver)
```

```bash
# host
kubectl run ipw-test --image=nginx:alpine
```

```text
pod/ipw-test created
```

With the backend still unreachable, every image is now admitted. This is the trade-off in one switch: fail closed protects the cluster and makes the webhook a dependency of every deployment; fail open keeps deployments working and silently removes the control during an outage.

---

## 5. Controlled Failure Scenario: Replacing the Plugin List

Edit the flag to list only the new plugin:

```yaml
- --enable-admission-plugins=ImagePolicyWebhook
```

The API server restarts and everything appears to work. What changed is invisible: `NodeRestriction` is no longer enabled, so a kubelet can once again modify Node and Pod objects that belong to other nodes. A hardening task has just weakened the cluster.

```bash
# node
grep enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml
```

Always read the current value of a list flag before changing it, and append. The same applies to `--authorization-mode`, where dropping `Node` or `RBAC` has similar consequences. Restore `NodeRestriction,ImagePolicyWebhook`.

---

## 6. Cleanup

```bash
# node
cp /root/backup/cks-08/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
rm -rf /etc/kubernetes/admission
```

```bash
# host
kubectl delete pod ipw-test
kubectl delete namespace vap-lab
kubectl delete validatingadmissionpolicybinding trusted-registries
kubectl delete validatingadmissionpolicy trusted-registries
```

If you enabled audit logging or encryption in earlier labs, restoring this backup keeps them only if the backup was taken after those labs. Check with `grep -E 'audit|encryption' /etc/kubernetes/manifests/kube-apiserver.yaml`.

---

## Further reading

- [Validating Admission Policy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
- [ImagePolicyWebhook](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#imagepolicywebhook)
- [Admission control reference](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)

## Next Lab

Proceed to **[[Kubernetes/labs/cks/09-image-signing-with-cosign|Lab CKS-09 — Image Signing with cosign]]**, or return to the [[Kubernetes/certifications/cks|CKS Track]].
