# AWS data and governance content review

Date: 2026-10-12. Independent, read-only content review; no content edits, deployment, build or test run was performed by this reviewer.

## Scope and evidence standard

Read the complete current bodies of all 50 notes in AWS/storage, databases, analytics, machine-learning and management-governance, including five new notes. Compared the 45 existing notes with HEAD using the HEAD file inventory, original section/code-block inventories and `git diff HEAD` rather than the index alone. Inspected original body excerpts for the concrete lost-depth findings below. This is not a claim that every sentence in every original was independently revalidated. Earlier remediation ledgers were not used as certificates.

P1 means a misleading consequential model or an example that fails under the stated/adjacent workflow. P2 means a substantive instructional gap: the requested operation cannot be reproduced without inventing missing setup, artifacts or request details. These are separate from false service claims. Line references describe the reviewed working-tree snapshot; subsequent parent edits may move or resolve them.

Three concrete semantic findings and twelve teaching/restoration findings follow. Their presence means the reviewed group is **not certified complete**. No P0 destructive or data-exposure instruction was confirmed. No live AWS account was used, so successful cloud execution is not asserted.

## Confirmed semantic findings

### DG01 — P1 — DynamoDB logical collection confused with physical partition

- Location: `content/AWS/databases/dynamodb/README.md:57`, with the neighboring PK/SK partition diagrams.
- Evidence: the sentence promises that every item sharing a PK is stored together. The original note had the same model; its restoration preserved an absolute that needs qualification.
- Reason: logical item collections/query ordering do not guarantee permanent physical colocation. AWS documents split-for-heat within an item collection by sort key when the table has no LSI; an LSI prevents that particular split. Capacity reasoning based on one immutable physical partition can therefore be wrong.
- Primary source: [AWS split-for-heat discussion](https://aws.amazon.com/blogs/database/part-2-scaling-dynamodb-how-partitions-hot-keys-and-split-for-heat-impact-performance/), particularly its LSI/no-LSI distinction. This is a placement caveat, not a guarantee adaptive capacity will fix a poor key design.
- Proposed fix: describe same-PK items as a logical item collection ordered by SK. Label partition drawings conceptual initial placement, add the no-LSI split caveat, and retain the warning about hot keys without making physical-layout promises.

### DG02 — P1 — ElastiCache examples collide across key data types

- Location: `content/AWS/databases/elasticache/README.md:67` and `:87`.
- Evidence: `HSET sandbox:user:123 name Alice` creates a hash. The later cache-aside function uses `sandbox:user:{user_id}` with GET and JSON strings. Calling `get_user("123", cache, load_user)` after the hash lesson performs GET on that hash.
- Reason: GET supports strings, not hashes; the natural sequential exercise raises WRONGTYPE before reaching the loader. The snippet's injected dependencies are clearly disclosed, but that does not prevent this deterministic fixture collision.
- Primary source: [Valkey GET engine contract](https://valkey.io/commands/get/) documents errors for non-string keys. This is an owning engine source rather than an unofficial Redis tutorial.
- Proposed fix: use disjoint type-aware prefixes, such as `sandbox:user-hash:123` and `sandbox:user-json:123`; demonstrate cache miss, second-call hit and expiry with an explicit loader/client fixture. Preserve exact-key cleanup and avoid global flushes.

### DG03 — P1 — Neptune SPARQL fence has no valid single-request invocation

- Location: `content/AWS/databases/neptune/README.md:64` through its SPARQL block at `:67`–`:80`.
- Evidence: prose asks the reader to submit to the remote endpoint, then one fence combines INSERT DATA and SELECT separated by a semicolon. It does not distinguish two submissions.
- Reason: Neptune's HTTP interface submits a query through `query=` and an update through `update=`. The combined block is not one valid query/update request. Sequential illustrative operations are legitimate—AWS also illustrates them—but this note lacks the submission boundary necessary to follow the example.
- Primary source: [Neptune SPARQL HTTP protocol](https://docs.aws.amazon.com/neptune/latest/userguide/access-graph-sparql-http-rest.html).
- Proposed fix: separate update and query fences and give their separate authenticated HTTPS request paths. Define the remote-client/IAM/network prerequisite and expected friend IRI; add bounded execution and exact sandbox triple cleanup. Do not replace this with a local rdflib query and call it Neptune validation.

## Confirmed teaching and restoration gaps

### DG04 — P2 — Glue incremental exercise has no bookmark-capable job

- Location: `content/AWS/analytics/glue/README.md:34`–`:38`, `:107`–`:117`.
- Evidence: the exercise asks for two unchanged-input runs followed by an added file, but the complete code demonstrates local pandas aggregation and catalog metadata, not a deployed Glue job with a supported source reader, stable transformation context, initialization/commit and bookmark argument. Those prerequisites appear only as prose.
- Original comparison: HEAD included Python-shell S3 read/write and a Spark transformation. Its claimed bookmark reader was incorrect and should stay removed; the useful end-to-end transformation/application wiring still needs an accurate replacement.
- Primary source: [Glue bookmark behavior and operational state](https://docs.aws.amazon.com/glue/latest/dg/monitor-continuations.html). Bookmarks are disabled by default; rewinding/resetting does not clean targets.
- Proposed fix: supply one complete supported Glue runtime job, tiny input files and expected totals; show role/script/job arguments, run/status handling and stable source context. Demonstrate zero new source input on run two, additional input on run three and an explicit duplicate-safe destination strategy. Keep the corrected local monthly aggregation as a separate introductory exercise.

### DG05 — P2 — Lake Formation authorization lesson lacks actual filter/grant wiring

- Location: `content/AWS/analytics/lake-formation/README.md:27`–`:33`, `:56`–`:67`.
- Evidence: all code was removed; readers are asked to grant finance-only rows and compare two principals but receive no table fixture, nested DataCellsFilter request, SELECT grant on that filter, opt-in/default-permission operations or expected result rows.
- Original comparison: original row filtering through LF-Tags and several SDK request shapes were wrong. They must not return. Replacing them with a generic setup list, however, does not teach the corrected authorization mechanism.
- Primary source: [Lake Formation data filtering](https://docs.aws.amazon.com/lake-formation/latest/dg/data-filtering.html) explains table-specific row/column filters and SELECT-only filtered grants.
- Proposed fix: choose full enforcement or hybrid access for one lab; provide a tiny catalog/S3 table, two principals, a valid nested filter request and corresponding grant. Explicitly handle IAMAllowedPrincipals/opt-in according to that mode and query exact expected/forbidden rows as each identity. Revoke only lab grants before removing the filter/catalog/data.

### DG06 — P2 — SageMaker training/deployment depth reduced to an unspecified example repository

- Location: `content/AWS/machine-learning/sagemaker/README.md:39`–`:45`, `:68`–`:78`, reference at `:123`.
- Evidence: the only executable blocks discover or create feature groups. The training/deployment sequence requires the reader to invent an entry point, dataset, runtime/container, training job, evaluation and inference payload. The repository-root reference does not select or pin an end-to-end example.
- Original comparison: HEAD had a concrete SKLearn estimator/training/deploy sequence plus tuning, autoscaling, pipelines and multi-model sections. Several imports, missing dependencies and API shapes were invalid; removal was justified, but the core custom-training workflow still has no substantive executable equivalent.
- Primary source: [AWS notebook-instance model-building tutorial](https://docs.aws.amazon.com/sagemaker/latest/dg/gs-console.html) provides a chosen setup/train/deploy/cleanup learning path.
- Proposed fix: select one maintained, version-pinned supported example and deep-link its exact notebook/script; provide synthetic data, complete entry point and request/serialization contract, expected held-out evidence, bounded status handling and endpoint cleanup. Explain multi-model vs single-model selection with one accurate replacement for the removed topic; avoid reviving costly distributed-GPU code merely for length.

### DG07 — P2 — EMR step has no matching application/input fixture

- Location: `content/AWS/analytics/emr/README.md:25`, `:38`–`:42`, `:65`–`:77`.
- Evidence: `example.py` is not supplied; the note explicitly disclaims an end-to-end lab. The subsequent bounded-job exercise still has no chosen application, small source fixture, output assertion or complete cluster recipe.
- Original comparison: original cluster/step/scaling shapes and timer interpretation needed correction. The useful cluster application and submission walkthrough has been replaced with contract warnings rather than a completed recipe.
- Primary source: [AWS EMR getting-started tutorial](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-gs.html) includes actual PySpark source, inputs, cluster submission and cleanup.
- Proposed fix: choose one EC2 Spark runtime/release, provide a small complete application and input, scoped role/network/log prerequisites and matching add-steps arguments. Record the expected output and terminal step status; deliberately fail an input path and observe failure before deleting only dedicated cluster/output artifacts.

### DG08 — P2 — FSx selected-product workflow has neither commands nor a selected walkthrough

- Location: `content/AWS/storage/fsx/README.md:30`–`:34`, `:59`–`:63`.
- Evidence: readers are told to deploy/mount the smallest suitable product through its owning guide, but references do not select a Windows or Lustre setup tutorial. The Windows/Lustre walkthrough comparison is a decision table, not creation/client instructions.
- Original comparison: Windows create/mount and Lustre create/mount examples existed. Literal passwords, platform-independent client-install assumptions, old performance figures and oversimplified S3 behavior should not be restored. Valid product-specific creation and mount teaching has no equivalent.
- Primary source: [FSx for Windows getting started](https://docs.aws.amazon.com/fsx/latest/WindowsGuide/getting-started.html) supplies product-specific AD, client/network, creation and access prerequisites.
- Proposed fix: make one Windows or Lustre lab concrete, with deployment/client prerequisites and current supported create schema/mount instructions, named checksummed files and restore assertions. Add an exact alternate-product walkthrough link rather than pretending one generic FSx command covers four products.

### DG09 — P2 — Storage Gateway API corrections do not form a usable gateway/share lab

- Location: `content/AWS/storage/storage-gateway/README.md:30`–`:36`, `:60`–`:70`.
- Evidence: activation/cache disks, role, ClientToken and client/authentication fields are named but no corrected activation/share request or client mount recipe remains. An outage experiment cannot begin from the supplied instructions alone.
- Original comparison: several original share fields and storage-class values were fabricated; original protocol/mount and gateway activation concepts were useful and require corrected replacements rather than only warnings.
- Primary source: [AWS File Gateway share creation](https://docs.aws.amazon.com/filegateway/latest/files3/GettingStartedCreateFileShare.html). NFS client-IP restrictions and SMB authentication/ACL choices differ; STS activation is also a prerequisite.
- Proposed fix: select an S3 File Gateway NFS lab with supported gateway/VM/disks/network requirements, scoped S3 role, persisted ClientToken, restricted ClientList and actual share path/mount. Test synchronized data and denied client before a bounded outage, then review queued uploads before teardown. Do not reinstate generic disk-format commands or unrestricted client defaults.

### DG10 — P2 — RDS failover/restore lab has no concrete engine/instance/data operation

- Location: `content/AWS/databases/rds/README.md:33`–`:37`, `:51`–`:71`.
- Evidence: the provisioning sequence only describes decisions. No current supported create request, client/TLS connection, SQL fixture, snapshot/PITR request or controlled failover command accompanies the exercise.
- Original comparison: original creation, read-replica, recovery and parameter-group examples had useful operational intent but unsafe literal passwords, stale version assumptions and overpromised failover timing. These errors are correctly gone; safe equivalents are still absent.
- Primary source: [RDS create-instance contract](https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_CreateDBInstance.html) and [point-in-time restore contract](https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_RestoreDBInstanceToPointInTime.html).
- Proposed fix: choose one supported PostgreSQL configuration with current version/class discovery, managed master secret, explicit private/encrypted networking and a TLS client recipe. Provide labelled rows, snapshot/PITR target and expected recovery checks, distinguish application reconnection from endpoint continuity, and show dedicated-resource cleanup including retained backups.

### DG11 — P2 — streaming replay lessons have no complete producer/consumer/state fixture

- Locations: `content/AWS/analytics/kinesis/data-streams.md:41`–`:45` and `:65`–`:75`; new `content/AWS/analytics/msk.md:21`–`:33`; new `content/AWS/analytics/managed-flink.md:21`–`:33`.
- Evidence: Kinesis has a one-record producer but no bounded consumer/stream setup. MSK has no chosen client/topic fixture, transactional boundary or duplicate-safe destination implementation. Flink links the real DataStream tutorial, but its proposed duplicate/late-event/window experiment does not specify the application modifications, fixture timestamps, watermark policy or expected totals.
- Original comparison: the original Kinesis KPL/KCL Python examples were not valid replacements for supported libraries. Their removal is correct. The actual consume/checkpoint/replay learning loop still needs to exist somewhere reachable and specific.
- Primary sources: [Kinesis GetRecords iterator contract](https://docs.aws.amazon.com/kinesis/latest/APIReference/API_GetRecords.html), [MSK getting started](https://docs.aws.amazon.com/msk/latest/developerguide/getting-started.html), [Flink DataStream tutorial](https://docs.aws.amazon.com/managed-flink/latest/java/getting-started.html).
- Proposed fix: give Kinesis a bounded one-shard demonstration with iterator advancement, base64 decoding and fixed duplicate IDs while explicitly excluding production reshard coordination. Pin a chosen MSK client recipe plus idempotent destination. For Flink, give fixed event-time/watermark/window parameters and checkpoint/restart expected outputs or label the current list an advanced experiment specification rather than a finished lab.

### DG12 — P2 — AI task examples lost despite supported corrected equivalents

- Locations: `content/AWS/machine-learning/ai-services/README.md:13`–`:28`, `:38`–`:49`; `content/AWS/machine-learning/comprehend/README.md:47`–`:57`; `content/AWS/machine-learning/rekognition/README.md:59`–`:85`.
- Evidence: AI-services now has only batch translation code. Comprehend has only PII code; Rekognition has only image-label code. Simple synchronous sentiment/entities, Polly speech/SSML, synchronous translation and non-sensitive text extraction examples disappeared; asynchronous video/custom-classifier lifecycles are generic sequences without corrected start/poll/page implementations. Lex and Kendra vanished from the service map and practical coverage.
- Original comparison: HEAD's simple detect_sentiment, detect_entities, synthesize_speech/AudioStream saving and translate_text schemas were substantially useful. Wrong PII Text fields, nonexistent streaming/Textract operations, unsafe sensitive imagery scenarios and fabricated custom-model requests must stay removed. These errors do not justify losing all neighboring valid workflows.
- Primary sources: [Comprehend sentiment contract](https://docs.aws.amazon.com/boto3/latest/reference/services/comprehend/client/detect_sentiment.html), [Polly synthesis contract](https://docs.aws.amazon.com/boto3/latest/reference/services/polly/client/synthesize_speech.html), [Lex V2](https://docs.aws.amazon.com/lexv2/latest/dg/what-is.html), [Kendra](https://docs.aws.amazon.com/kendra/latest/dg/what-is-kendra.html).
- Proposed fix: restore small synthetic task examples with correct current fields and explicit input/output expectations; give at least one real bounded async polling/pagination workflow. Restore Lex as V2 and Kendra decision/contract links, clearly distinguishing generations and cost. Do not reintroduce guarantees of exact model scores or unsupported universal language/feature tables.

### DG13 — P2 — CDK cross-stack teaching and comparison removed wholesale

- Location: `content/AWS/management-governance/cdk/README.md:15`–`:21`, `:95`–`:101`.
- Evidence: the current minimal bucket and assertion are useful, but no replacement demonstrates cross-stack inputs/outputs or explains deployment dependencies. The former CDK/CloudFormation/Terraform comparison and cross-stack snippets disappeared.
- Original comparison: HEAD's CfnOutput/Fn.importValue example had a valid core; original Aspects/Pipelines snippets were incomplete and its comparison contained misleading state/drift claims. Fixing those portions does not require removing cross-stack ownership/dependency teaching.
- Primary source: [AWS CDK resource references](https://docs.aws.amazon.com/cdk/v2/guide/resources.html), including cross-stack references and their CloudFormation constraints.
- Proposed fix: add a small two-stack example with actual constructor props or explicit export/import and explain same-environment dependency/deletion constraints. Replace the inaccurate comparison with ownership/state/lifecycle distinctions; provide a completed tiny Aspect or link a specific supported recipe instead of restoring the placeholder checker.

### DG14 — P2 — Systems Manager command execution lacks the observation command

- Location: `content/AWS/management-governance/systems-manager/README.md:29`–`:42`, `:85`–`:94`.
- Evidence: a valid SendCommand is provided, but the reader must invent per-node output/status polling; ordinary start-session and protected Parameter Store operational examples have also become prose-only. The note warns submission is not execution without completing the demonstration of that distinction.
- Original comparison: HEAD included get-command-invocation and start-session; incorrect session-log schema, hybrid activation fields and broad fleet writes were correctly removed. Read-only result inspection and tightly scoped session/parameter workflows could have been preserved.
- Primary source: [GetCommandInvocation contract](https://docs.aws.amazon.com/cli/latest/reference/ssm/get-command-invocation.html), including per-invocation state and eventual consistency.
- Proposed fix: capture CommandId, show bounded polling for the selected node with terminal/failure states, and display only non-sensitive stdout. Add one session recipe with plugin/logging prerequisites and one synthetic parameter operation with exact cleanup; keep tunnel-content audit limitations and secret-output warnings.

### DG15 — P2 — new governance/BI and visual-ML drills require undefined artifacts

- Locations: `content/AWS/management-governance/guardrails-and-resource-sharing.md:27`–`:38`; `content/AWS/analytics/lakehouse-and-bi.md:27`–`:39`; `content/AWS/machine-learning/sagemaker-canvas/README.md:27`–`:33`, `:56`–`:67`.
- Evidence: the guardrail drill does not choose a shared resource, RAM request/permission or narrow guardrail/action pair. The BI drill omits the source rows and RLS permissions dataset. Canvas does not select a supplied labelled dataset, target, exact supported UI path or expected prediction contract. These are useful experiment outlines but not reproducible completed lessons.
- Original comparison: the first two are new; Canvas's invented SDK operations should remain excluded, but supported visual setup is still an outline.
- Primary sources: [RAM invitations](https://docs.aws.amazon.com/ram/latest/userguide/working-with-shared-invitations.html), [Quick reader RLS](https://docs.aws.amazon.com/quick/latest/userguide/restrict-access-to-a-data-set-using-row-level-security.html), [Canvas workflows](https://docs.aws.amazon.com/sagemaker/latest/dg/canvas.html).
- Proposed fix: choose one Resolver-rule or TGW share and real allowed/denied action pair, preserving owner/dependency cleanup. Supply BI source CSV plus rules CSV for actual readers, specify rules-dataset creation and warn that a named user's blank restricted-field rule permits all values. Give Canvas one tiny synthetic dataset and supported target/build/prediction procedure with expected evidence rather than a fabricated SDK replacement.

## Explicit coverage

Every row means the complete current body was read. “No new confirmed defect” is not a clean bill: it means no additional concrete defect was established in this pass. HEAD comparison means original structure/change comparison, plus targeted removed-body inspection for reported omissions—not live deployment or exhaustive verification of all original claims.

| Path below content/AWS                                   | Original comparison and current review outcome                                                                                                                                                                                   |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| storage/README.md                                        | HEAD hierarchy/decision patterns compared; current service decisions, access/recovery tradeoffs read; no new confirmed defect.                                                                                                   |
| storage/ebs/README.md                                    | HEAD creation/mount/snapshot/performance sections compared; current guarded device handling and gp3 arithmetic read; no new confirmed defect.                                                                                    |
| storage/ebs/amazon-data-lifecycle-manager.md             | Original short stub compared; current policy prerequisites, snapshot lifecycle and recovery exercise read; no new confirmed defect.                                                                                              |
| storage/efs/README.md                                    | HEAD mounts/access points/throughput/lifecycle compared; current TLS/IAM/POSIX and restore detail read; no new confirmed defect.                                                                                                 |
| storage/fsx/README.md                                    | Product setup/mount excerpts compared; DG08. Product distinctions restored, runnable selected-product access still missing.                                                                                                      |
| storage/glacier/README.md                                | HEAD vault/S3 lifecycle distinction compared; current historical vault boundaries and current restore lifecycle read; no new confirmed defect.                                                                                   |
| storage/s3/README.md                                     | HEAD object/policy/lifecycle/replication/static-site sections compared; current private-first workflow, versioning and examples read; no new confirmed defect.                                                                   |
| storage/s3/protection-and-recovery.md                    | New; full recovery/versioning/Object Lock body read; no new confirmed defect.                                                                                                                                                    |
| storage/storage-gateway/README.md                        | Activation/share/mount excerpts compared; DG09; corrected architecture and cache/queue boundaries retained.                                                                                                                      |
| databases/README.md                                      | HEAD choice tree/HA/cache patterns compared; current selection/recovery discussion read; no new confirmed defect.                                                                                                                |
| databases/rds/README.md                                  | Creation/replica/restore/parameter excerpts compared; DG10. Correct HA distinction retained.                                                                                                                                     |
| databases/aurora/README.md                               | HEAD endpoints/Serverless/Global/Backtrack sections compared; current cluster-instance sequence read. Missing encryption flag was investigated and rejected as a factual defect; see below.                                      |
| databases/dynamodb/README.md                             | HEAD model/operations/index/capacity sections compared; DG01. Conditional writes/capacity arithmetic read.                                                                                                                       |
| databases/elasticache/README.md                          | HEAD datatype/cache/scaling sections compared; DG02. Cache failure and engine distinctions read.                                                                                                                                 |
| databases/documentdb/README.md                           | HEAD CRUD/aggregation/transactions/sharding/recovery sections compared; current compatibility caveats and aggregation body read; no new confirmed defect. Setup remains guide-dependent, not independently deployed.             |
| databases/neptune/README.md                              | HEAD traversal/SPARQL/bulk-load sections compared; DG03. Language/control/data-plane boundaries read.                                                                                                                            |
| databases/qldb/README.md                                 | HEAD journal/digest/API sections compared; current retired-service historical guidance read; no new active-lab claim confirmed.                                                                                                  |
| databases/timestream/README.md                           | HEAD query/interpolation/write sections compared; current variant restrictions and writer/query read. Upsert exercise and interpolation remain insufficiently worked; see unresolved follow-up.                                  |
| databases/redshift/README.md                             | HEAD duplicate warehouse implementation compared; current canonical analytics link and operational-to-analytical architecture read. Consolidation is reasonable, not itself lost depth.                                          |
| analytics/README.md                                      | HEAD lambda/kappa/batch patterns compared; current architecture, boundaries and table format decisions read; no new confirmed defect.                                                                                            |
| analytics/athena/README.md                               | HEAD DDL/partition/formats/query sections compared; current labelled partition and SDK polling fixtures read; no new confirmed defect.                                                                                           |
| analytics/emr/README.md                                  | HEAD launch/step/bootstrap/scaling excerpts compared; DG07. Corrected seconds/role/step contracts read.                                                                                                                          |
| analytics/glue/README.md                                 | HEAD pandas/Spark/bookmark excerpts compared; DG04. Current monthly local core/catalog/trigger schemas read.                                                                                                                     |
| analytics/lake-formation/README.md                       | HEAD filter/grant/LF-Tag excerpts compared; DG05. Current full/hybrid enforcement distinction read.                                                                                                                              |
| analytics/redshift/README.md                             | HEAD distribution/WLM/loading/view/maintenance sections compared; current SQL and COPY/UNLOAD workflow read; no new confirmed SQL defect.                                                                                        |
| analytics/opensearch/README.md                           | HEAD mapping/query/lifecycle/FGAC sections compared; current mapping/search and refresh/tier/auth boundaries read; no new confirmed defect.                                                                                      |
| analytics/kinesis/README.md                              | HEAD ingestion patterns/service comparison compared; current Firehose/Flink/MSK boundaries read; no new confirmed defect.                                                                                                        |
| analytics/kinesis/data-streams.md                        | HEAD producer/consumer/capacity sections compared; DG11. Current producer and replay semantics read.                                                                                                                             |
| analytics/kinesis/data-firehose.md                       | HEAD destinations/transform/retries compared; current transform contract/error handling and delivery caveats read; no new confirmed defect.                                                                                      |
| analytics/kinesis/data-analytics.md                      | HEAD SQL/window content compared; current historical SQL boundary and supported Flink migration read; no new active retired-product instruction confirmed.                                                                       |
| analytics/msk.md                                         | New; full ordering/offset/effect/replay body read; DG11.                                                                                                                                                                         |
| analytics/managed-flink.md                               | New; full event-time/checkpoint/late-event/replay body read; DG11. Exact official tutorial exists, but the advanced experiment is unspecified.                                                                                   |
| analytics/lakehouse-and-bi.md                            | New; full engine/format/BI/RLS exercise read; DG15. Owner bypass independently confirmed.                                                                                                                                        |
| machine-learning/README.md                               | HEAD stack/choice/privacy sections compared; current baseline/evaluation/lifecycle decisions read; no new confirmed defect.                                                                                                      |
| machine-learning/ai-services/README.md                   | HEAD task/API snippets inspected; DG12. Current batch translation and task contract corrections read.                                                                                                                            |
| machine-learning/bedrock/README.md                       | HEAD inference/RAG/agent/guardrail sections compared; current Converse code and model/tool/retrieval/privacy boundaries read. Current retention behavior verified; no new confirmed API defect.                                  |
| machine-learning/sagemaker/README.md                     | HEAD estimator/deploy/scaling/pipeline excerpts inspected; DG06. Current Feature Store schema read.                                                                                                                              |
| machine-learning/sagemaker-canvas/README.md              | HEAD fictional SDK/build/deploy coverage compared; DG15. Supported workflow/limits described but no actual visual fixture.                                                                                                       |
| machine-learning/comprehend/README.md                    | HEAD sentiment/entity/PII excerpts inspected; DG12. Current offset display and pricing arithmetic read.                                                                                                                          |
| machine-learning/rekognition/README.md                   | HEAD image/video/custom-label excerpts inspected; DG12. Current simple label request is retained; async schemas need worked equivalents.                                                                                         |
| management-governance/README.md                          | HEAD governance/service architecture compared; current account/principal/OU distinctions and controlled rollout read; no new confirmed defect.                                                                                   |
| management-governance/organizations/README.md            | HEAD hierarchy/delegation/policy sections compared; current example/SCP exceptions read; current OU/SCP/account quotas independently confirmed.                                                                                  |
| management-governance/organizations/delegated-admin.md   | Original conceptual body compared; current service-specific principals/registration/revocation body read; no new confirmed defect.                                                                                               |
| management-governance/control-tower/README.md            | HEAD landing-zone/factory/drift sections compared; current control types/enrollment/drift guidance read; no new confirmed defect. Concrete chosen control exercise remains guide-dependent.                                      |
| management-governance/cli/README.md                      | HEAD install/profile/query/pagination/troubleshooting sections compared; current profile/pagination/JMESPath body read; no new confirmed command defect. Installation/autocompletion walkthrough was not restored.               |
| management-governance/cloudformation/README.md           | HEAD template/change/drift/nested/StackSet sections compared; current complete isolated public/private network template and lifecycle read; no new confirmed template defect.                                                    |
| management-governance/cdk/README.md                      | HEAD cross-stack/assertion/Aspect/comparison excerpts inspected; DG13. Current minimal app/assertion body read.                                                                                                                  |
| management-governance/systems-manager/README.md          | HEAD command output/session/parameter/hybrid sections compared; DG14. Current hybrid pricing and tunnel logging limitation read.                                                                                                 |
| management-governance/systems-manager/patch-manager.md   | HEAD fleet scenario/approval/reboot/report sections compared; current OS-specific rollout and package reporting read; no new confirmed defect. Baseline/Quick Setup deployment remains a design plan rather than a complete lab. |
| management-governance/guardrails-and-resource-sharing.md | New; full guardrail/share boundary and drill read; DG15.                                                                                                                                                                         |

## Verified claims and rejected suspicions

- Aurora new-cluster encryption: do **not** report the current create example's missing StorageEncrypted flag as proof it creates an unencrypted cluster. AWS documents default encryption for all new clusters from February 18, 2026. Explicit key selection may still be necessary for customer-managed-key requirements. [Aurora encryption](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Overview.Encryption.html).
- Current Organizations numbers in the lesson match its owning quota page: OU count, SCP document size, default/new-account qualification and qualified account increases. These should not be “corrected” back to old limits. [Organizations quotas](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_reference_limits.html).
- Systems Manager hybrid pricing in the lesson matches the June/September 2026 transition and operation-based rates; EC2 and hybrid remain distinct. [Current Systems Manager pricing](https://aws.amazon.com/systems-manager/pricing/).
- Bedrock's current retention modes and legacy provider_data_share non-sharing behavior match its owning page. Customer inference logs remain separate; the old universal no-retention claim should not return. [Bedrock retention](https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html).
- Quick reader/owner RLS distinction is supported. A reader isolation test must not use a dataset owner. Rules files also have consequential blank-value semantics, which should be taught in a concrete fixture. [Quick RLS](https://docs.aws.amazon.com/quick/latest/userguide/restrict-access-to-a-data-set-using-row-level-security.html).
- The retired QLDB and Kinesis SQL material is presented historically. Restoring historical diagrams/queries does not authorize active deployment recipes for retired services.

## Unresolved or deliberately limited observations

1. Timestream `databases/timestream/README.md:69` computes a new timestamp on each execution while the exercise requests rewriting the same identity at higher Version. This is not a false upsert claim: the prose correctly specifies same identity. A useful follow-up is to capture/reuse the timestamp and demonstrate Version 2 plus stale-version rejection explicitly. Its former interpolation SQL was also invalid; current prose is accurate but not a worked interpolation replacement. [WriteRecords version semantics](https://docs.aws.amazon.com/timestream/latest/APIReference/API_WriteRecords.html). Classified as incomplete demonstration, not confirmed execution failure of a promised rerun.
2. No chosen live runtime/version was deployed for DocumentDB, Aurora, OpenSearch, Redshift, SageMaker, Canvas or streaming services. Engine-specific compatibility, quotas and full role/network permissions remain account/environment verification tasks; conceptual correctness is not a certificate of live readiness.
3. The standalone new MSK/Flink/BI/guardrail notes can serve as conceptual modules if labelled that way. DG11/DG15 apply when their experiment lists are counted as completed practical lessons, as required by the current depth-remediation request.
4. Current source bodies were fully read, but all price/feature/lifecycle claims in 50 notes were not individually rebrowsed. Official sources were used for questionable consequential findings and the explicit false-positive checks above. No claim that every niche statement is verified is made.
5. CLI installation/autocompletion and some former per-engine tuning/connection examples remain omitted. No unsafe instruction was established from these omissions alone. If the objective includes every useful original workflow, restore them using current owning installation/engine guidance rather than copying stale HEAD snippets.

## Handoff

Fix DG01–DG03 first, then supply the concrete artifacts/requests and expected-result paths in DG04–DG15. Keep factual corrections, retired-service notices, safe cleanup and current references. A build or syntax check cannot resolve these semantic and teaching findings. Re-review changed bodies and their example assumptions after fixes; this report intentionally leaves findings open rather than equating inventory completion with remediation completion.
