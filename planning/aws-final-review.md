# Independent final AWS review

Reviewed 2026-10-12 during the root agent's integration pass. This agent changed no published note in this review task. Findings were sent immediately to root; status below reflects follow-up reads, not deployment certification.

## Concrete findings and disposition

| ID   | Priority | Exact note/context                                                                                               | Counterexample and required correction                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Follow-up status                                                                                                                 |
| ---- | -------- | ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| FR01 | P0       | `serverless/app-runner/README.md`, opening and Sandbox deployment exercise; serverless service selection         | The lab was offered to any sandbox account, but App Runner closed to new customers March 31, 2026. Scope to existing eligible customers and direct new users to ECS/Express Mode. [CreateService notice](https://docs.aws.amazon.com/apprunner/latest/api/API_CreateService.html), [availability/migration guide](https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html).                                                                                                               | Root added notice, eligible-account prerequisite and migration sources; observed in follow-up read.                              |
| FR02 | P1       | `networking/load-balancing/README.md`, original Pricing Examples                                                 | Monthly requests cannot determine ALB capacity units without the other dimensions. Sustained 10 Gbps gives about 4,500 GB/hour, not ten NLCUs; at the old example's $0.006 rate that alone is about $19,440 over 720 hours. [Capacity pricing dimensions](https://aws.amazon.com/elasticloadbalancing/pricing/).                                                                                                                                                                                                     | Root replaced speculative prices with a dimensional model.                                                                       |
| FR03 | P1       | Same LB note, original opening/Components/Key Features/Limits and no sandbox lab                                 | Three-type claim contradicted GWLB; ALB listener described as TCP; mandatory EIPs and unsourced universal numeric limits were overgeneralized. [ALB listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html), [ELB product/price scope](https://aws.amazon.com/elasticloadbalancing/pricing/). Replace with scoped protocol/addressing/health guidance and target registration, failure/recovery and cleanup.                                                    | Root rewrote lesson with four offerings and a reversible two-target lab; observed.                                               |
| FR04 | P1       | `networking/vpc/transit-gateway.md`, original Attachments/Associations/Shared VPC/Gotchas                        | A route alone does not let a source AZ lacking an enabled attachment subnet reach TGW. Same table does not imply all reachability; association does not imply propagation. Static aggregates/longest-prefix routing exist; the overlapping-VPC example was not a valid summarization lesson. [AZ/route behavior](https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html).                                                                                                                         | Root rewrote these boundaries and added segmentation/return-path exercises; observed.                                            |
| FR05 | P1       | Same TGW note, original last Gotcha                                                                              | Organization recipients do not universally accept invitations: with RAM organization sharing enabled, access is automatic; other cases differ. [RAM invitations](https://docs.aws.amazon.com/ram/latest/userguide/working-with-shared-invitations.html).                                                                                                                                                                                                                                                             | Root corrected sharing versus attachment/routing controls; observed.                                                             |
| FR06 | P1       | `networking/vpc/network-acls.md`, Sandbox exercise step 2                                                        | Applying the displayed 192.0.2.0/24 documentation-only rules literally blocks an ordinary real client, so the stated success checkpoint cannot occur. Substitute the verified sandbox client CIDR before association.                                                                                                                                                                                                                                                                                                | Root added explicit substitution instruction; observed.                                                                          |
| FR07 | P1       | `compute/ecs/README.md` one-off prerequisite/image; `compute/batch/README.md` job prerequisite/image             | Both use public.ecr.aws but previously allowed vague endpoint-only networking. Specify approved public-image egress or a private mirror with required endpoint paths and Logs reachability. [Fargate networking](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html), [ECR endpoint scope](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html). Current ECR docs mention Public SDK endpoint support; do not extrapolate that to every Docker pull path. | Root clarified public egress/private mirror and log reachability in both prerequisites; observed.                                |
| FR08 | P1       | `foundations/getting-started.md`, Authenticate versus First deployment; `compute/lambda/README.md`, copyable CLI | SSO commands verify --profile wiki-sandbox, but linked mutation commands omit profile/Region and no session export is established. A production default profile remains a concrete wrong-account counterexample. Establish task-scoped AWS_PROFILE/workload Region and recheck identity in that exact context, or use explicit flags consistently. [CLI configuration precedence](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html).                                                         | Root added explicit sandbox profile/Region shell handoff, identity stop-check and Lambda cross-link; observed in follow-up read. |
| FR09 | P1       | `serverless/app-runner/README.md`, cleanup order                                                                 | DeleteService rejects an active VPCIngressConnection; delete dedicated ingress connections before service deletion, not afterward. [DeleteService contract](https://docs.aws.amazon.com/apprunner/latest/api/API_DeleteService.html).                                                                                                                                                                                                                                                                                | Root reordered cleanup explicitly; observed.                                                                                     |

## Tests and rejected false positives

- Executed only the pure local Python handler from the Lambda note against a valid direct-invoke fixture, a minimal HTTP-shaped dictionary and invalid numeric name. Greeting/default greeting and ValueError expectations passed. No AWS resources or credential documents were accessed.
- Checked the HTTP quick-create route contract. Its managed default route **key** cannot be changed as an ordinary route edit; authorization can be updated. The IAM authorization extension is therefore not reported as a false API defect. [UpdateRoute](https://docs.aws.amazon.com/cli/latest/reference/apigatewayv2/update-route.html), [IAM authorization](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-access-control-iam.html).
- IAM/STS distinctions, standard versus advanced Lambda modes, classic/network firewall stages and cache isolation were reviewed against source-linked boundaries. Syntax or HTTP availability alone is not a service-level execution test.
- Root owns navigation/format/source-availability/build checks. Known transient directory-link failures were not duplicated as new substantive findings.

## Audit coverage comparison

The N/C corrections are represented by stateful SG/stateless NACL return paths, ALB health/TLS/ingress, endpoint resources, REJECT metadata, firewall ordering, TGW routing/pricing, VPN identity, alias/cache behavior, usage-key limits, Lambda/Fargate/Inspector/KMS fixes and repaired launch/task examples (the last two security services were handled in this agent's earlier scoped pass).

New foundations, six-pillar/data-store architecture, IAM evaluation/Identity Center/STS, Backup/DRS, Auto Scaling/ECR, delivery, tracing, quotas/Health, private/hybrid DNS, WAF/Shield/Firewall Manager, global networks, MSK and Flink lessons now exist and provide decision boundaries, exercises and primary sources. This does **not** certify the entire missing-topic matrix or every cross-linked Kubernetes implementation. Several new lessons intentionally provide guided/versioned workflows rather than copy-and-run infrastructure templates; they explicitly require sandbox prerequisites and do not claim deployed validation.

## Full-body review coverage

Read all 48 following note bodies; reviewed selected code and source contracts as described above. This is substantive coverage, not a generic clean bill for every quota/version claim.

- [AWS/compute/README.md](../content/AWS/compute/README.md)
- [AWS/compute/ec2/README.md](../content/AWS/compute/ec2/README.md)
- [AWS/compute/lambda/README.md](../content/AWS/compute/lambda/README.md)
- [AWS/compute/ecs/README.md](../content/AWS/compute/ecs/README.md)
- [AWS/compute/eks/README.md](../content/AWS/compute/eks/README.md)
- [AWS/compute/ecr.md](../content/AWS/compute/ecr.md)
- [AWS/compute/auto-scaling.md](../content/AWS/compute/auto-scaling.md)
- [AWS/compute/batch/README.md](../content/AWS/compute/batch/README.md)
- [AWS/compute/lightsail/README.md](../content/AWS/compute/lightsail/README.md)
- [AWS/networking/README.md](../content/AWS/networking/README.md)
- [AWS/networking/vpc/README.md](../content/AWS/networking/vpc/README.md)
- [AWS/networking/vpc/security-groups.md](../content/AWS/networking/vpc/security-groups.md)
- [AWS/networking/vpc/network-acls.md](../content/AWS/networking/vpc/network-acls.md)
- [AWS/networking/vpc/vpc-peering.md](../content/AWS/networking/vpc/vpc-peering.md)
- [AWS/networking/vpc/transit-gateway.md](../content/AWS/networking/vpc/transit-gateway.md)
- [AWS/networking/vpc/vpn.md](../content/AWS/networking/vpc/vpn.md)
- [AWS/networking/load-balancing/README.md](../content/AWS/networking/load-balancing/README.md)
- [AWS/networking/networking-security/README.md](../content/AWS/networking/networking-security/README.md)
- [AWS/networking/hybrid/README.md](../content/AWS/networking/hybrid/README.md)
- [AWS/networking/cdn/README.md](../content/AWS/networking/cdn/README.md)
- [AWS/networking/dns/README.md](../content/AWS/networking/dns/README.md)
- [AWS/networking/private-access-and-hybrid-dns.md](../content/AWS/networking/private-access-and-hybrid-dns.md)
- [AWS/networking/protection-and-inspection.md](../content/AWS/networking/protection-and-inspection.md)
- [AWS/networking/global-network-services.md](../content/AWS/networking/global-network-services.md)
- [AWS/serverless/README.md](../content/AWS/serverless/README.md)
- [AWS/serverless/lambda/README.md](../content/AWS/serverless/lambda/README.md)
- [AWS/serverless/api-gateway/README.md](../content/AWS/serverless/api-gateway/README.md)
- [AWS/serverless/api-gateway/usage-plan.md](../content/AWS/serverless/api-gateway/usage-plan.md)
- [AWS/serverless/app-runner/README.md](../content/AWS/serverless/app-runner/README.md)
- [AWS/foundations/README.md](../content/AWS/foundations/README.md)
- [AWS/foundations/getting-started.md](../content/AWS/foundations/getting-started.md)
- [AWS/architecture/README.md](../content/AWS/architecture/README.md)
- [AWS/architecture/well-architected.md](../content/AWS/architecture/well-architected.md)
- [AWS/architecture/data-store-selection.md](../content/AWS/architecture/data-store-selection.md)
- [AWS/reliability/README.md](../content/AWS/reliability/README.md)
- [AWS/reliability/backup-and-recovery.md](../content/AWS/reliability/backup-and-recovery.md)
- [AWS/developer-tools/README.md](../content/AWS/developer-tools/README.md)
- [AWS/operations/README.md](../content/AWS/operations/README.md)
- [AWS/operations/quotas-health-and-support.md](../content/AWS/operations/quotas-health-and-support.md)
- [AWS/concepts/vpc-lattice.md](../content/AWS/concepts/vpc-lattice.md)
- [AWS/concepts/magic-ips-169.254.md](../content/AWS/concepts/magic-ips-169.254.md)
- [AWS/concepts/app-mesh-vs-vpc-lattice.md](../content/AWS/concepts/app-mesh-vs-vpc-lattice.md)
- [AWS/security/iam/policy-evaluation.md](../content/AWS/security/iam/policy-evaluation.md)
- [AWS/security/iam/identity-center.md](../content/AWS/security/iam/identity-center.md)
- [AWS/security/iam/sts-and-federation.md](../content/AWS/security/iam/sts-and-federation.md)
- [AWS/monitoring/tracing-and-observability.md](../content/AWS/monitoring/tracing-and-observability.md)
- [AWS/analytics/msk.md](../content/AWS/analytics/msk.md)
- [AWS/analytics/managed-flink.md](../content/AWS/analytics/managed-flink.md)

## Scope boundaries

No live AWS deploy/invoke/association/delete calls were made. IAM trust roles, subnet paths, certificate ownership, broker/stream clients and real failure/restore drills still require an authorized sandbox/budget. All nine concrete review findings have observed root corrections; they remain listed for traceability. This is not certification of unexecuted deployments, the full missing-topic matrix or every cross-linked implementation.

## Final matrix appendix: three late-added lessons

Read the full bodies of [Cognito](../content/AWS/security/cognito.md), [guardrails/RAM](../content/AWS/management-governance/guardrails-and-resource-sharing.md) and [lakehouse/BI](../content/AWS/analytics/lakehouse-and-bi.md). Reviewed against current owning contracts; no published notes were edited by this reviewer.

**FR10 (P1 teaching/test completeness, Cognito):** the original exercise reused the greeting backend and one user but expected cross-tenant resource denial. That backend has no tenant resource/authorization check, so the stated test is not executable. Separate the sign-in/scope test from a two-user/two-resource backend extension that implements tenant authorization before expecting denial. Also explicitly connect resource-server custom scope creation, app-client allowed scopes, PKCE requested scopes and matching route scope; a vague API scope does not create that configuration. Root correction observed: explicit wiki-api/read resource-server/client/request/route scope chain, missing-scope rejection, and a separate two-user/two-resource backend isolation extension with authoritative claims and cleanup. [Cognito resource servers/scopes](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-define-resource-servers.html), [HTTP JWT checks](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html).

Guardrails/RAM: reviewed permission ceilings, management/service-linked exceptions, owner/consumer responsibility, invitation scope and rollback. No concrete new defect found in the bounded workflow; the drill is not a deployed policy template. [SCP evaluation](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_evaluation.html), [RAM recipient behavior](https://docs.aws.amazon.com/ram/latest/userguide/working-with-shared-invitations.html).

Lakehouse/BI: current primary documentation independently confirms Quick Sight is the BI feature of Amazon Quick and existing QuickSight APIs/SDKs remain unchanged. Reader-versus-owner RLS distinction is correct: dataset owners can see all rows. Format/catalog/engine interoperability and SPICE freshness are appropriately conditional. No concrete new blocker found; reader isolation, refresh and engine compatibility still require actual sandbox execution. [Current product boundary](https://docs.aws.amazon.com/quick/latest/userguide/what-is.html), [RLS owner/reader semantics](https://docs.aws.amazon.com/quick/latest/userguide/restrict-access-to-a-data-set-using-row-level-security.html).

Total full-body independent coverage is now **51 notes**. This appendix does not claim all-account/all-edition compatibility or successful deployment.
