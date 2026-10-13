---
title: "Amazon Neptune"
description: "Neptune serves graph workloads where traversing relationships is central: fraud rings, identity graphs, recommendations and knowledge graphs."
tags:
  - aws/databases
date: 2026-10-12
---

# Amazon Neptune

Neptune serves graph workloads where traversing relationships is central: fraud rings, identity graphs, recommendations and knowledge graphs. Prerequisites: [[AWS/architecture/data-store-selection|data-store selection]], [[AWS/networking/README|networking]] and [[AWS/security/iam/README|IAM]].

## Data models and services

A Neptune Database cluster can store property graphs and RDF. Gremlin and openCypher query the property-graph model; SPARQL queries RDF. These languages do not query across the two models automatically, but choosing one does not force a separate engine/cluster for the other.

Neptune Analytics is a distinct analytical graph service, useful for large-scale algorithms and analytical workloads. Neptune ML adds graph machine-learning workflows with documented training/inference integrations. Do not treat Database, Analytics and ML as synonyms or promise every algorithm in every deployment.

Design vertices/edges or RDF triples from actual questions. Index/label/property and traversal choices affect fan-out and latency; a graph database does not eliminate pathological unbounded queries.

## Provisioning, loading and authorization

CreateDBCluster and CreateDBInstance are separate operations. A cluster call does not accept num-instances and does not create all compute through an invented instance-class flag. Use private networking and TLS, and configure IAM database authentication where required.

Bulk loading is an HTTPS data-plane loader request to the cluster with S3 source access/IAM role, not aws neptune start-load. API administrative credentials and query authentication have different roles. A Python rdflib graph running locally is not a Neptune connection; use the documented remote SPARQL/Gremlin/openCypher endpoint with its authentication.

## Relationship-query exercise

Create a budgeted sandbox through the owning guide, with a permitted client in reachable networking. Load a tiny graph of customers, accounts and transfers. Express a bounded two-hop question in one supported language and inspect the result. Add a negative authorization test and a query deadline; large traversals should not hang indefinitely.

Verify bulk-load status/errors and counts plus representative relationships. If testing recovery, restore into an isolated target and repeat the traversal. Record actual failover/reconnect behavior. Remove disposable instances/clusters, load data and reviewed snapshots; Analytics graphs or ML endpoints created separately require separate cleanup.

## Cost and operational decisions

Choose instance-based/serverless Database or Analytics from workload support rather than a generic graph-price table. Budget compute, storage, I/O, backups, transfer and any ML resources. Monitor query latency/errors, memory/CPU, replication and load failures using mode-specific metrics. Capacity/engine/version/Region limits are sourced discovery inputs, not timeless universal ceilings.

## Property graph versus RDF

```text
Property graph:
(Alice:Person {age:35}) -[knows {since:2020}]-> (Bob:Person)

RDF:
subject          predicate       object
ex:Alice         foaf:name       "Alice"
ex:Alice         foaf:knows      ex:Bob
```

Property graphs model labelled vertices/edges and properties, queried through supported Gremlin/openCypher. RDF models triples and vocabularies, queried with SPARQL. One cluster can support both models; it does not make their languages interchangeable or automatically join them.

## Concrete traversal examples

These are Gremlin-language examples for a configured remote session, not JavaScript client initialization. They use explicit synthetic IDs and mutate only the labelled test graph.

```text
g.addV('Person').property(T.id, 'sandbox-alice').property('name', 'Alice')
g.addV('Person').property(T.id, 'sandbox-bob').property('name', 'Bob')
g.V('sandbox-alice').addE('knows').to(g.V('sandbox-bob'))
g.V('sandbox-alice').out('knows').values('name')
g.V('sandbox-alice').out('knows').out('knows').dedup()
g.V('sandbox-alice').out('knows').count()
```

For RDF, submit an update and query as **two separate requests**. Save this update as `neptune-lab-insert.rq`; the named graph is reserved exclusively for this lab:

```sparql
PREFIX ex: <http://example.org/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
INSERT DATA {
  GRAPH <http://example.org/cloudnative-wiki-neptune-lab> {
    ex:SandboxAlice a ex:Person ;
      foaf:name "Alice" ;
      foaf:knows ex:SandboxBob .
  }
}
```

Save the following separately as `neptune-lab-query.rq`:

```sparql
PREFIX ex: <http://example.org/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
SELECT ?friend WHERE {
  GRAPH <http://example.org/cloudnative-wiki-neptune-lab> {
    ex:SandboxAlice foaf:knows ?friend .
  }
} LIMIT 10
```

Do not mistake a local rdflib SELECT for a Neptune request. For openCypher, test its supported query/features against the property graph and use the owning HTTP/client authentication path.

### Authenticated remote submission and exact cleanup

Use an existing disposable IAM-authenticated Neptune Database cluster with a DB instance, a client able to reach its private HTTPS port 8182, Python `boto3`/`requests`, and temporary credentials allowing `neptune-db:ReadDataViaQuery`, `neptune-db:WriteDataViaQuery` and `neptune-db:DeleteDataViaQuery` on that cluster resource. The deletion action is needed specifically for the named-graph cleanup; do not grant cluster-wide query deletion casually on a shared production graph. [Neptune data-plane actions](https://docs.aws.amazon.com/neptune/latest/userguide/iam-dp-actions.html). Set NEPTUNE_LAB_ENDPOINT to its actual `https://...:8182` endpoint and configure the matching AWS Region. The control-plane `neptune` client does not execute SPARQL, and `neptunedata` does not currently provide SPARQL operations.

```python
import os
from pathlib import Path
from urllib.parse import urlencode
import requests
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.session import Session

session = Session()
region = session.get_config_variable("region")
assert region, "Configure the cluster's AWS Region"
endpoint = os.environ["NEPTUNE_LAB_ENDPOINT"].rstrip("/")
assert endpoint.startswith("https://"), "Keep TLS enabled"

def sparql(kind, statement):
    assert kind in {"update", "query"}
    credentials = session.get_credentials()
    if credentials is None:
        raise RuntimeError("No AWS credentials available")
    body = urlencode({kind: statement})
    request = AWSRequest(
        method="POST", url=endpoint + "/sparql", data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded",
                 "Accept": "application/sparql-results+json"},
    )
    SigV4Auth(credentials.get_frozen_credentials(), "neptune-db", region).add_auth(request)
    result = requests.post(request.url, data=body,
                           headers=dict(request.headers), timeout=(5, 30))
    result.raise_for_status()
    return result

sparql("update", Path("neptune-lab-insert.rq").read_text())
result = sparql("query", Path("neptune-lab-query.rq").read_text()).json()
friends = [row["friend"]["value"] for row in result["results"]["bindings"]]
assert friends == ["http://example.org/SandboxBob"], friends
print(friends)
```

An IAM identity lacking the read action should receive an authorization failure, not an empty graph. Client socket timeouts bound client waiting, not necessarily server execution; set the cluster's supported query timeout and keep traversals/results bounded before larger tests. If a request times out, inspect its outcome before retrying mutations.

After verification, call the same helper with `sparql("update", "CLEAR GRAPH <http://example.org/cloudnative-wiki-neptune-lab>")`, then repeat the query and expect no bindings. Clear only this dedicated graph, never all graphs. Remove dedicated cluster/instances and retained snapshots through the earlier recovery-aware teardown if you created them. [SPARQL query/update request fields](https://docs.aws.amazon.com/neptune/latest/userguide/access-graph-sparql-http-rest.html), [AWS Python IAM signing](https://docs.aws.amazon.com/neptune/latest/userguide/iam-auth-connecting-python.html).

## Bulk loading, analytics and operations

Bulk loading requires supported source formats in S3, a scoped role and the cluster's data-plane loader endpoint. Submit the request, capture load ID, inspect errors/completion and reconcile representative edges/triples. A created cluster without DB instances is not a complete query deployment.

Neptune Analytics serves separate graph analytical/algorithm workloads; Neptune ML has explicit export/training/inference resource flows. These capabilities introduce their own permissions, cost and cleanup; do not infer that a Database instance supplies every analytics/ML operation.

Monitor query latency/errors, CPU/memory, connections, replica lag and load failures for the actual deployment. Bound traversal depth/time and compare indexed lookup patterns with unbounded graph scans. Document the restore path for both graph data and external role/network/client configuration.

## References

- [Neptune graph query languages](https://docs.aws.amazon.com/neptune/latest/userguide/access-graph.html)
- [Neptune cluster CLI contract](https://docs.aws.amazon.com/cli/latest/reference/neptune/create-db-cluster.html)
- [Bulk loader](https://docs.aws.amazon.com/neptune/latest/userguide/bulk-load.html)
- [Neptune Analytics](https://docs.aws.amazon.com/neptune-analytics/latest/userguide/what-is-neptune-analytics.html)
- [Neptune ML](https://docs.aws.amazon.com/neptune/latest/userguide/machine-learning.html)
- [Neptune pricing](https://aws.amazon.com/neptune/pricing/)
