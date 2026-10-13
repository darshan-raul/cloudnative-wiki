---
title: "Lab CKAD-09 — Ingress"
tags: [kubernetes, labs, ckad, cka, cks, ingress, tls, traefik]
date: 2026-10-13
description: "Install an Ingress controller, route by host and path to two Services with an Ingress resource, and terminate TLS with a certificate stored in a Secret."
---

# Lab CKAD-09 — Ingress

[[Kubernetes/labs/ckad/05-services-and-dns|Lab CKAD-05]] stops at Services and NodePorts. The Ingress resource is listed in the CKAD and CKA curricula, and "properly set up Ingress with TLS" is a CKS objective, so this lab covers it on its own.

Concepts: [[Kubernetes/concepts/L04-services-networking/04-ingress|Ingress]] and [[Kubernetes/guides/troubleshooting/ingress-404|Ingress 404 / 502 / 503]].

Tested 2026-10-13 on kind v0.33.0 with Kubernetes v1.37.0.

Verified on `kind` v0.31 with Kubernetes v1.35.0 and the Traefik Helm chart.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**.
- Helm 3 or 4 on your machine.
- NodePorts `30080` and `30443` free. [[Kubernetes/labs/ckad/05-services-and-dns|Lab CKAD-05]] uses `30080` and deletes its Service at the end; check with `kubectl get service -A | grep -E '30080|30443'`, which should print nothing.
- No other lab is required. Both backends use the public `podinfo` image.

### Install an Ingress controller

An Ingress resource does nothing until a controller watches it. In the exam a controller is already installed. Here, install Traefik and expose it on fixed NodePorts; [[Kubernetes/guides/networking/traefik|Traefik]] has the details.

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik
helm install traefik traefik/traefik --version 41.7.1 -n traefik --create-namespace \
  --set service.type=NodePort \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443
kubectl -n traefik rollout status deployment/traefik --timeout=180s
kubectl get ingressclass
```

```text
NAME                CONTROLLER                      PARAMETERS   AGE
traefik (default)   traefik.io/ingress-controller   <none>       20s
```

The IngressClass name is what goes in `spec.ingressClassName`. Check it first in every Ingress task. `(default)` means an Ingress that names no class is given this one; do not rely on that in a task that names a class.

If the install fails with `provided port is already allocated`, another Service holds one of the NodePorts. A NodePort is allocated once for the whole cluster, whatever the namespace.

The lab cluster publishes both NodePorts on your machine, so the controller answers on `127.0.0.1:30080` (HTTP) and `127.0.0.1:30443` (HTTPS). On a cluster created without those mappings, run `kubectl -n traefik port-forward svc/traefik 30080:80 30443:443` in another terminal instead.

---

## 2. Two Backends

```bash
kubectl create namespace ing-lab
kubectl -n ing-lab create deployment web --image=ghcr.io/stefanprodan/podinfo:6.7.1 --port=9898
kubectl -n ing-lab create deployment api --image=ghcr.io/stefanprodan/podinfo:6.7.1 --port=9898
kubectl -n ing-lab set env deployment/web PODINFO_UI_MESSAGE="web backend"
kubectl -n ing-lab set env deployment/api PODINFO_UI_MESSAGE="api backend"
kubectl -n ing-lab expose deployment web --port=80 --target-port=9898
kubectl -n ing-lab expose deployment api --port=80 --target-port=9898
kubectl -n ing-lab rollout status deployment/web --timeout=90s
kubectl -n ing-lab rollout status deployment/api --timeout=90s
```

---

## 3. Route by Host and Path

`kubectl create ingress` writes the manifest for you. Each `--rule` is `host/path=service:port`, and a trailing `*` on the path means `Prefix` instead of `Exact`:

```bash
kubectl -n ing-lab create ingress shop --class=traefik \
  --rule="shop.example.com/=web:80" \
  --rule="shop.example.com/api*=api:80" \
  --dry-run=client -o yaml
```

```yaml
spec:
  ingressClassName: traefik
  rules:
    - host: shop.example.com
      http:
        paths:
          - backend:
              service:
                name: web
                port:
                  number: 80
            path: /
            pathType: Exact
          - backend:
              service:
                name: api
                port:
                  number: 80
            path: /api
            pathType: Prefix
```

Create it by running the same command without `--dry-run=client -o yaml`, then test. The `Host` header selects the rule:

```bash
curl -s -H 'Host: shop.example.com' http://127.0.0.1:30080/ | grep message
curl -s -H 'Host: shop.example.com' http://127.0.0.1:30080/api/info | grep message
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: other.example.com' http://127.0.0.1:30080/
```

```text
  "message": "web backend",
  "message": "api backend",
404
```

The two backends are the same image with a different message, so the response shows which one answered. The third request is a `404` because no rule matches that host.

| `pathType`               | `/api` matches                             |
| :----------------------- | :----------------------------------------- |
| `Exact`                  | `/api` only                                |
| `Prefix`                 | `/api`, `/api/`, `/api/info`, not `/apiv2` |
| `ImplementationSpecific` | Whatever the controller decides            |

---

## 4. Terminate TLS

Create a certificate and store it in a TLS Secret in the **same namespace** as the Ingress:

```bash
openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=shop.example.com" -addext "subjectAltName=DNS:shop.example.com"

kubectl -n ing-lab create secret tls shop-tls --cert=tls.crt --key=tls.key
```

Add a `tls` section whose host matches the rule's host:

```bash
kubectl -n ing-lab patch ingress shop --type=merge \
  -p '{"spec":{"tls":[{"hosts":["shop.example.com"],"secretName":"shop-tls"}]}}'
```

```yaml
spec:
  tls:
    - hosts:
        - shop.example.com
      secretName: shop-tls
```

Test over HTTPS and **verify** the certificate against the one you created, instead of switching verification off with `-k`. `--resolve` makes `curl` use the right name for SNI and for the certificate check without touching `/etc/hosts`:

```bash
curl -s --cacert tls.crt --resolve shop.example.com:30443:127.0.0.1 https://shop.example.com:30443/ | grep message
curl -s --cacert tls.crt --resolve other.example.com:30443:127.0.0.1 https://other.example.com:30443/; echo "exit=$?"
```

```text
  "message": "web backend",
exit=60
```

The first request succeeds only if the controller presented your certificate for that name. The second fails with `curl` exit code 60 (certificate verification failed): for a host with no `tls` entry the controller presents its own default certificate, which your file does not vouch for. If the first request also fails with 60, the Secret name, the namespace or the `hosts` entry does not match.

To look at what was served, add `-v` and read the `subject:` and `issuer:` lines.

---

## 5. Controlled Failure Scenario: Three Ways to Get a 404 or 503

Break the Ingress in three different ways and compare the symptoms.

**Wrong IngressClass.** No controller claims the resource:

```bash
kubectl -n ing-lab patch ingress shop --type=merge -p '{"spec":{"ingressClassName":"nginx"}}'
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: shop.example.com' http://127.0.0.1:30080/
kubectl -n ing-lab get ingress shop
kubectl -n ing-lab patch ingress shop --type=merge -p '{"spec":{"ingressClassName":"traefik"}}'
```

The request returns `404`. The Ingress still exists and looks healthy in `kubectl get ingress`; the only clue is the `CLASS` column naming a class that `kubectl get ingressclass` does not list.

**Wrong Service port.** The route exists but points nowhere:

```bash
kubectl -n ing-lab patch ingress shop --type=json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":8081}]'
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: shop.example.com' http://127.0.0.1:30080/
kubectl -n ing-lab describe ingress shop | grep -A6 Rules
kubectl -n ing-lab patch ingress shop --type=json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":80}]'
```

Traefik drops a route whose Service port does not exist, so this is also a `404`. `kubectl describe ingress` shows the backend as `web:8081`, which is not a port the Service exposes.

**No ready endpoints.** The Service is right but has no Pods behind it:

```bash
kubectl -n ing-lab scale deployment web --replicas=0
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: shop.example.com' http://127.0.0.1:30080/
kubectl -n ing-lab get endpointslices -l kubernetes.io/service-name=web
kubectl -n ing-lab scale deployment web --replicas=1
```

This time the answer is `503`: the route is valid, but the EndpointSlice has no endpoints to send the request to.

Work from the outside in: IngressClass, then the rule's host and path, then the Service name and port, then the endpoints.

---

## 6. Cleanup

```bash
kubectl delete namespace ing-lab
helm uninstall traefik -n traefik && kubectl delete namespace traefik
rm -f tls.key tls.crt
```

---

## Further reading

- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
- [TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)

## Next Lab

Proceed to **[[Kubernetes/labs/ckad/10-jobs-cronjobs-and-multi-container-pods|Lab CKAD-10 — Jobs, CronJobs & Multi-Container Pods]]**, or return to the [[Kubernetes/certifications/ckad|CKAD Track]].
