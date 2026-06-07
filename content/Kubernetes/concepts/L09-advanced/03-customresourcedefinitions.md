# CustomResourceDefinitions (CRDs)

*"https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/"*

A CRD is how you **add a new object type to the Kubernetes API**. Once registered, your custom resource is first-class — `kubectl get` it, apply RBAC to it, watch it like any other object.

## The point

Built-in k8s objects (Pod, Service, ConfigMap) cover the basics. Most production needs more:

* Application CRs — `RedisCluster`, `Postgres`, `KafkaCluster`, `Certificate`
* Platform CRs — `IngressRoute`, `Gateway`, `ClusterIssuer`
* Tenant CRs — `Tenant`, `Project`, `Quota`

You can write these without CRDs, but you'd lose the kubectl, RBAC, status conditions, watch loops, and tooling that come with native k8s objects. **CRDs are how k8s extends itself.**

## Basic example

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: crontabs.stable.example.com
spec:
  group: stable.example.com
  scope: Namespaced
  names:
    plural: crontabs
    singular: crontab
    shortNames: [ct]
    kind: CronTab
    listKind: CronTabList
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              cronSpec:
                type: string
              image:
                type: string
              replicas:
                type: integer
                minimum: 1
                maximum: 10
    additionalPrinterColumns:           # shown in kubectl get
    - name: Schedule
      type: string
      jsonPath: .spec.cronSpec
    - name: Age
      type: date
      jsonPath: .metadata.creationTimestamp
    subresources:
      status: {}                         # separate .status from .spec
```

After `kubectl apply`, the new type is registered:

```bash
kubectl get crontabs
kubectl create -f my-crontab.yaml
```

```yaml
# my-crontab.yaml
apiVersion: stable.example.com/v1
kind: CronTab
metadata:
  name: my-tab
spec:
  cronSpec: "* * * * *"
  image: my-cron-image:latest
  replicas: 3
```

## Key fields in the CRD

| Field | Purpose |
|---|---|
| `group` | API group the new type belongs to (e.g. `stable.example.com`) |
| `scope` | `Namespaced` or `Cluster` (cluster-scoped = like a Node, namespaced = like a Pod) |
| `names.plural/singular/kind` | What to call it in the API |
| `versions[].served` | Whether this version is served by the API |
| `versions[].storage` | Which version is used to store the data (exactly one) |
| `versions[].schema` | OpenAPI v3 schema for validation |
| `versions[].subresources.status` | Adds a `.status` field separate from `.spec` |
| `versions[].subresources.scale` | Lets HPA scale this CR (k8s 1.16+) |
| `additionalPrinterColumns` | Columns shown by `kubectl get` |
| `conversion` | How to convert between versions (if you have multiple) |

## Schema validation

The OpenAPI schema is enforced at admission. A Pod with `replicas: 100` (above the `maximum: 10` in the example) will be **rejected by the API server**, not by your controller.

This is a huge win — you get free validation for every custom resource, just like built-in types.

## Conversions

If you have multiple versions, you have to provide a conversion. Two options:

* **None** — only one version at a time; clients must request that version
* **Webhook** — call out to a service that converts between versions; needed for round-trip upgrades

For most CRDs, **start with one version**. Add more only when you need them.

## Gotchas

* **Once a CRD is `Established`, removing it deletes all data.** All instances of the custom resource are deleted. Treat CRDs as dangerous deletes.
* **`spec.scope: Cluster` means the resource is cluster-scoped**, like a Node or ClusterRole. You can have a `Tenant` that's cluster-wide, but a `RedisCluster` should usually be namespaced.
* **The schema is required in v1** (CRD API v1, GA since k8s 1.16). Old `apiextensions.k8s.io/v1beta1` CRDs without a schema are not allowed anymore.
* **CRD validation happens at admission, not runtime.** A field can be empty in a stored object if the schema is later relaxed.
* **A CRD does nothing by itself.** It defines the schema; you need a **controller** (or operator) to actually do something with the instances.
* **CRD names must be unique cluster-wide**, in the form `<plural>.<group>`. Pick something specific to your domain.
* **Status is opt-in** via `subresources: status: {}`. Without it, `.status` is part of `.spec` and changes are not observable via watch.
* **Webhook conversion is a separate deployment** — you have to run a conversion webhook service for multi-version CRDs.

## CRDs vs Aggregated API Servers

| | CRD | Aggregated API Server |
|---|---|---|
| Where it runs | In the kube-apiserver | As a separate pod, registered via APIService |
| Performance | Good for low/moderate volume | Better for high-volume or complex APIs |
| Complexity | Low | High — you run a whole API server |
| Use case | Most cases | Subresources, custom auth, very high QPS |

**Start with CRDs.** Move to aggregated API servers only if CRDs can't do what you need.

## Related

* [[Kubernetes/concepts/L09-advanced/02-custom-controllers|Custom Controllers]] — the controller that watches your CRs
* [[Kubernetes/concepts/L09-advanced/01-operators|Operators]] — CRD + custom controller + operational knowledge
* [[Kubernetes/concepts/L09-advanced/07-aggregation-layer|Aggregation Layer]] — the underlying mechanism for APIServices
