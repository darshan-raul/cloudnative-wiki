---
title: Application Discovery Service
description: AWS Application Discovery Service — discovers on-premises infrastructure (servers, dependencies, utilization) via agentless and agent-based collectors, exports data for migration planning
tags:
  - aws/migration
date: 2026-10-12
---

# Application Discovery Service

Prerequisites: [[AWS/security/iam/README|temporary-credential IAM roles]], [[AWS/networking/vpc/README|VPC routing]] and the [[AWS/migration/README|migration acceptance/rollback plan]].

Application Discovery Service collects supported infrastructure information for migration planning. It closed to new customers on November 7, 2025; existing customers may continue, while new customers should evaluate AWS Transform.

## Distinct collectors and lifecycle

The Agentless Collector is not the retired Discovery Connector. The old Connector reached full shutdown November 17, 2025. A Discovery Agent can collect supported process/network dependency information; do not promise that the Agentless Collector supplies the same dataset. [[AWS/migration/migration-evaluator/README|Migration Evaluator's collector]] is another distinct tool.

Select the discovery home Region and verify supported platform/Region/permission prerequisites before installation. Do not paste copied installer commands or promise an unsupported fixed ninety-day retention period.

## Availability-scoped discovery exercise

This workflow is for eligible existing customers; it is not a new-customer signup lab.

1. Establish owner approval and data classification for infrastructure inventory. Review collector IAM, network egress and supported source platform.
2. In the console follow the current Agentless Collector or Discovery Agent installation guide for the actual source. Select the home Region before starting collection.
3. Collect a representative period including peaks, batch jobs and maintenance, then inspect source completeness.
4. Export supported datasets and analyze them through the documented analytics workflow. An exported dataset can be queried; the service does not have a fictional arbitrary SQL-query API.
5. Validate dependency hypotheses with application owners: absence of observed traffic is not proof of no dependency.
6. Stop collection and remove only the disposable collector/agent and credentials according to the owning uninstall workflow. Preserve/delete collected data according to its retention policy.

## Real API inventory

Supported operations include describe-agents, list-configurations, describe-configurations, start-data-collection-by-agent-ids and start-export-task. There are no start-agentless-collector-scan, list-agents or list-servers commands in this service. Agent controls apply to agents, not interchangeably to all collector products.

Use the owning CLI schemas and console-export workflow instead of fabricated deployment flags. Check collection/export status and errors rather than assuming a successful API invocation means all servers were discovered.

## Assessment quality

Include hardware, performance, licensing, storage, network and application ownership. Cross-check inventory counts against CMDB/hypervisor records and quantify missing hosts/time periods. Discovery evidence informs the [[AWS/migration/README|migration strategy]]; it does not automatically approve a seven-R classification.

## Collector capability and planning table

| Source                         | Typical evidence                                                          | Limitation to verify                                  |
| ------------------------------ | ------------------------------------------------------------------------- | ----------------------------------------------------- |
| Discovery Agent                | Supported host configuration/utilization and process/network dependencies | OS/version, collection permissions and agent coverage |
| Agentless Collector            | Supported inventory/performance and collector modules                     | Not equivalent to agent process/network telemetry     |
| Existing CMDB/import           | Declared inventory/ownership                                              | Freshness, missing hosts and supported import schema  |
| Migration Evaluator Collector  | Business-case discovery/sizing evidence                                   | Separate product/workflow, not an ADS agent           |
| Historical Discovery Connector | Archived connector context only                                           | Fully shut down; not current Agentless Collector      |

```text
authorized source → selected collector/agent → home-Region inventory
                                             ├─ collection/status checks
                                             ├─ documented exports
                                             └─ portfolio/dependency assessment
```

Each row needs source count, observation interval and collection-quality evidence. Server name/CPU count alone cannot establish an application's network dependency or licensing requirement.

## Data collected and dependency interpretation

Record stable server/configuration IDs, hostname, IP/address changes, OS/architecture, hardware capacity, utilization windows and provenance. Where a supported agent records process/connections, correlate communicating endpoints/time windows and ask owners what the connection means.

A dependency edge is observed evidence, not a guaranteed complete application topology. Scheduled jobs, DR links, DNS/service discovery and encrypted/proxied connections can complicate interpretation. Separate an absent observation from confirmed absence.

## Supported read/export API walkthrough

For an eligible existing-customer environment, inspect real configurations rather than fictional list-servers or SQL APIs:

```bash
aws discovery describe-agents
aws discovery list-configurations --configuration-type SERVER
aws discovery describe-configurations --configuration-ids CONFIGURATION_ID
aws discovery describe-export-tasks
```

Use returned IDs, filters/pagination and the actual home Region. Agent collection starts through start-data-collection-by-agent-ids for supported agent IDs; it is not the agentless collector scan command.

For a documented CSV export workflow:

```bash
aws discovery start-export-task --export-data-format CSV
```

Record exportId, inspect describe-export-tasks and the returned destination/download artifact contract. Protect exports because names, addresses, processes and topology may reveal sensitive infrastructure. Query them through the supported analytics/data-source path; the Discovery API itself is not arbitrary SQL.

## Deployment and monitoring runbook

Agent/OVA download, installation arguments, supported platform sizing and uninstall paths come from the current owning guide. Validate downloaded artifacts/source, collection credentials, network/DNS egress and source-account read access; use the actual supported installer and service controls for that platform.

Confirm each intended host/configuration is represented and collection status is recent. Compare discovered counts with authoritative inventory and flag stale/missing sources. Use documented collection/export status rather than guessed HostAgentHeartbeat/DataSize metrics.

Before planning a wave, validate observed peaks, storage/network requirements, identity/license dependencies and owner acceptance. Stop/dispose only lab collection and revoke its credentials; preserve approved exports and delete sensitive artifacts according to policy.

References: [agent/collector guide](https://docs.aws.amazon.com/application-discovery/latest/userguide/what-is-appdiscovery.html), [CLI inventory](https://docs.aws.amazon.com/cli/latest/reference/discovery/list-configurations.html), [export contract](https://docs.aws.amazon.com/cli/latest/reference/discovery/start-export-task.html), [data collection](https://docs.aws.amazon.com/cli/latest/reference/discovery/start-data-collection-by-agent-ids.html).

## References

- [Availability change](https://docs.aws.amazon.com/application-discovery/latest/userguide/application-discovery-service-availability-change.html)
- [Feature retirement table](https://docs.aws.amazon.com/general/latest/gr/full_shutdown_services.html)
- [Discovery CLI contracts](https://docs.aws.amazon.com/cli/latest/reference/discovery/)
- [Discovery workflow](https://docs.aws.amazon.com/migrationhub/latest/ug/gs-new-user-discovery.html)
