# Targeted execution evidence for the certification-track critique

Review date: 2026-10-13. These are targeted reproductions, not full runs of all 28 labs.

Environment: Linux; kind 0.31.0; kubectl 1.36.0; isolated single-node Kubernetes 1.35.0 cluster named `wiki-critic`, with a separate temporary kubeconfig. Node image: `kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f`. Single-node topology suffices for the selector, apply, API, UID and NodePort checks; no multi-node scheduling conclusion was derived from it.

The default Deployment and ConfigMap/Secret manifests were extracted from the Markdown. The configuration check reproduces the retained environment from CKAD-03, applies CKAD-04, adds its invalid reference, and reapplies its suggested recovery. The SSA check is a reduced reproduction of CKAD-07's identical ownership transitions. NodePort validation uses two Services to reproduce the allocation conflict without installing Traefik. Runtime checks used the exact podinfo 6.7.1 image.

## Core results

```text
NAME         IMAGE
kindnet      docker.io/kindest/kindnetd:v20251212-v0.29.0-alpha-105-g20ccfc88
kube-proxy   registry.k8s.io/kube-proxy:v1.35.0
pod/rogue-pod created
{"matchLabels":{"app.kubernetes.io/name":"podinfo","pod-template-hash":"7d548d9599"}}
uid=100(app) gid=101(app) groups=101(app)
POST panic status=405
{
  "code": 400,
  "message": "cache server is offline"
}
cache status=200
deployment.apps/podinfo env updated
configmap/podinfo-config created
secret/podinfo-secret created
deployment.apps/podinfo configured
Waiting for deployment "podinfo" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "podinfo" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "podinfo" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "podinfo" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "podinfo" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "podinfo" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "podinfo" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "podinfo" rollout to finish: 1 old replicas are pending termination...
deployment "podinfo" successfully rolled out
PODINFO_UI_COLOR=#16a085
PODINFO_UI_MESSAGE=v2 rollout successful!
deployment.apps/podinfo patched
deployment.apps/podinfo configured
[{"name":"PODINFO_TOKEN","valueFrom":{"secretKeyRef":{"key":"api-token","name":"podinfo-secret"}}},{"name":"PODINFO_UI_COLOR","value":"#16a085"},{"name":"PODINFO_UI_MESSAGE","value":"v2 rollout successful!"},{"name":"DB_PASSWORD","valueFrom":{"secretKeyRef":{"key":"missing-password-key","name":"podinfo-secret"}}}]
Running owner=
```

The cache response body reports code 400 and "cache server is offline" even though the observed HTTP status was 200. The important result is failure to write persistent data; do not characterize this trace as an HTTP 400.

## Additional results

```text
namespace/net-review created
deployment.apps/server created
service/server exposed
pod/client created
Waiting for deployment "server" rollout to finish: 0 of 1 updated replicas are available...
deployment "server" successfully rolled out
pod/client condition met
{
  "commit": "6b7aab8a10d6ee8b895b0a5048f4ab0966ed29ff",
  "version": "6.7.1"
}networkpolicy.networking.k8s.io/default-deny-all created
wget: bad address 'server:9898'
command terminated with exit code 1
service/first created
error: failed to create NodePort service: Service "second" is invalid: spec.ports[0].nodePort: Invalid value: 30080: provided port is already allocated
deployment.apps/ssa-review serverside-applied
deployment.apps/ssa-review scaled
deployment.apps/ssa-review image updated
error: Apply failed with 2 conflicts: conflicts with "kubectl" with subresource "scale" using apps/v1:
- .spec.replicas
conflicts with "kubectl-set" using apps/v1:
- .spec.template.spec.containers[name="podinfo"].image
Please review the fields above--they currently have other managers. Here
are the ways you can resolve this warning:
* If you intend to manage all of these fields, please re-run the apply
  command with the `--force-conflicts` flag.
* If you do not intend to manage all of the fields, please edit your
  manifest to remove references to the fields that should keep their
  current managers.
* You may co-own fields by updating your manifest to match the existing
  value; in this case, you'll become the manager if the other manager(s)
  stop managing the field (remove it from their configuration).
See https://kubernetes.io/docs/reference/using-api/server-side-apply/#conflicts
```

A repeat of the network check failed while default-deny was present and succeeded immediately after policy deletion. Therefore this review does **not** claim the tested default kind CNI ignores NetworkPolicy. The CKS-01 criticism is missing behavioural tests and remediation completeness. The test above establishes DNS denial on this specific environment, not a complete NetworkPolicy conformance check.

## Other checks

- `kubectl run monster-pod --image=busybox --restart=Never --requests='cpu=100,memory=256Gi' --dry-run=client -o yaml -- sleep 3600` returned exit 1, `error: unknown flag: --requests`.
- After CKAD-04 recovery, the broken Pod remained in `CreateContainerConfigError` and the Deployment still included `DB_PASSWORD` referencing `missing-password-key`.
- After applying CKAD-04, the Deployment no longer had the readiness probe originally supplied in CKAD-02.
- `npm run check:k8s` passed: 1021 notes scanned, zero errors and warnings in the Kubernetes report. This is structural validation, not technical correctness validation.
- The isolated review cluster was removed after the checks; existing clusters were not targeted.

## Provenance of defects

Checked `git show HEAD:<old lab path>`: the old versions already contained the rogue-Pod example, ConfigMap reapply recovery, `/cache/k8s-curriculum`, `kubectl run --requests`, `POST /panic`, the server-side-apply drift example, and the root-user claim. Those defects are inherited into the new tracks. This review judges the material learners now encounter; it does not attribute all defects to the latest session.
