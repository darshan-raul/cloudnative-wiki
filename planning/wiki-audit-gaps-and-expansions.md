# Comprehensive Knowledge Graph Audit: Gaps, Inconsistencies & Expansion Roadmap

> **Audit Scope:** Complete top-down analysis of all 1,001 markdown notes across 11 core knowledge domains in Darshan's CloudNative Wiki (Quartz v4 static digital garden).
> **Date of Audit:** October 4, 2026 | **Status:** Read-Only Audit Complete (Zero files modified, zero git commits).

---

## Executive Summary & System Health Dashboard

This audit performed an exhaustive, top-down programmatic and architectural inspection of every markdown document in `content/`. The wiki contains exceptional, deep engineering curriculum in areas like Kubernetes (L00–L09 + EKS track), Azure, GCP, and OpenTelemetry. However, the knowledge graph suffers from severe structural asymmetries, legacy migration artifacts from GitBook, broken internal links, syntax errors, and abandoned stubs.

### Global Metrics at a Glance

| Metric                                | Count     | Severity    | Impact Description                                                                          |
| :------------------------------------ | :-------- | :---------- | :------------------------------------------------------------------------------------------ | --- | ------------------------------------- |
| **Total Markdown Files**              | **1,001** | Reference   | 11 top-level domains covering cloud infrastructure, DevOps, AI, and systems                 |
| **Broken Wikilinks (`[[...]]`)**      | **114**   | 🔴 Critical | Visitors hit 404 or dead ends; broken references between architecture and concepts          |
| **Directory-Targeted Wikilinks**      | **74**    | 🟠 High     | Wikilinks pointing to folders instead of markdown pages, triggering Quartz folder listings  |
| **Stub Notes (<80 words)**            | **142**   | 🟠 High     | Placeholder notes with little to no explanatory text                                        |
| **Raw Link 'Bookmark' Notes**         | **99**    | 🟡 Medium   | Notes containing solely raw YouTube, Twitter/X, or GitHub links with zero written synthesis |
| **Broken GitBook Image/Asset Embeds** | **25**    | 🔴 Critical | Dead `<img src="../../.gitbook/assets/...">` references from legacy GitBook migrations      |
| **Missing YAML Frontmatter**          | **331**   | 🟡 Medium   | Notes lacking `---` frontmatter, breaking Quartz title, tags, description indexing          |
| **Syntax Errors / Unclosed Fences**   | **13**    | 🔴 Critical | Odd number of ` ``` ` code fences and `                                                     |     | ` table errors breaking parser layout |
| **Orphaned Notes (0 Inbound Links)**  | **186**   | 🟡 Medium   | Valid content unreachable from the knowledge graph unless searched directly by name         |
| **Phantom Curriculum Modules**        | **19**    | 🔴 Critical | Modules explicitly outlined and linked in README files that do not exist on disk            |

### Domain-by-Domain Quantitative Breakdown

| Domain                 | File Count | Avg Word Count | Stubs (<80w) | Raw Link Dumps | Broken Links | Dir Links | Health Status                                   |
| :--------------------- | :--------- | :------------- | :----------- | :------------- | :----------- | :-------- | :---------------------------------------------- |
| **ROOT (Hub Pages)**   | 11         | 603            | 1            | 0              | 28           | 68        | 🔴 Critical Structural Issues                   |
| **Kubernetes & EKS**   | 264        | 1,720          | 0            | 0              | 0            | 0         | 🟢 High Depth (67 missing frontmatter)          |
| **AWS Cloud**          | 166        | 815            | 19           | 1              | 5            | 0         | 🟠 Asymmetric (Legacy `concepts/` ghost folder) |
| **Azure Platform**     | 49         | 1,547          | 0            | 0              | 0            | 0         | 🟢 Production Grade & Uniform                   |
| **GCP Platform**       | 57         | 1,561          | 0            | 0              | 0            | 0         | 🟢 Production Grade & Uniform                   |
| **Linux & Kernel**     | 106        | 791            | 2            | 0              | 3            | 0         | 🟡 Good depth; Root hub disconnected            |
| **AI & LLMs**          | 49         | 685            | 10           | 7              | 1            | 1         | 🟠 LangChain/LangGraph great, stubs elsewhere   |
| **Architecture**       | 172        | 850            | 53           | 43             | 54           | 1         | 🔴 19 phantom auth modules + 43 link dumps      |
| **DevOps & DevSecOps** | 26         | 2,283          | 0            | 0              | 7            | 0         | 🔴 Missing CI/CD, GitOps, Platform Engg hubs    |
| **Security & SIEM**    | 30         | 566            | 0            | 0              | 16           | 4         | 🟠 Wazuh strong; endpoint folders empty         |
| **Observability**      | 0 (Folder) | N/A            | 1            | 0              | 0            | 0         | 🔴 Missing top-level folder; OTel stranded      |
| **Resources & Guides** | 71         | 82             | 57           | 46             | 0            | 0         | 🔴 80% bookmark dump / broken GitBook assets    |

---

## Part 1: Vault-Wide Architectural & Navigational Defects (Level 0)

### 1.1 The Root Hub Duality Problem (`<Domain>.md` vs `<Domain>/README.md`)

In Quartz v4, navigating to a section can occur either via a root-level markdown file `content/<Domain>.md` or a directory readme `content/<Domain>/README.md`. A severe divergence exists between what is presented on the home page (`content/index.md`) and what exists inside the directories:

1. **Linux Section Disconnect:**
   - `content/index.md` links to `[[Linux]]`, which resolves to `content/Linux.md` (a 30-line outdated file).
   - `content/Linux.md` links to non-existent notes: `[[Linux/editors]]`, `[[Linux/tools/package-manager]]`, `[[Linux/tools/file-based]]`, `[[Linux/configuration-management-tools]]`, and `[[Kubernetes/concepts/networking/networking]]`.
   - Meanwhile, `content/Linux/README.md` is a 3,602-byte index correctly linking all 10 real Linux modules (`concepts`, `kernel`, `networking`, `storage`, `users-groups`, `boot-init`, `security`, `virtualization`, `packaging`, `observability`). Visitors entering via `[[Linux]]` never see these!

2. **DevOps Section Disconnect:**
   - `content/index.md` links to `[[DevOps]]`, resolving to `content/DevOps.md`.
   - `content/DevOps.md` promises CI/CD (`[[DevOps/ci-cd/README]]`), GitHub Actions (`[[DevOps/ci-cd/github-actions]]`), Git (`[[DevOps/ci-cd/git]]`), and Platform Engineering (`[[DevOps/devops-sre-platform-engg/README]]`).
   - **None of these folders or files exist.** The only subdirectory inside `content/DevOps/` is `devsecops/`.

3. **Observability Structural Anomaly:**
   - `content/index.md` promotes `[[Observability]]` as one of four Supporting Topics.
   - But **no `content/Observability/` directory exists** in the repository!
   - `content/Observability.md` is a 27-line stub that links to `Resources/guides/observability/prometheus` and `Resources/guides/observability/open-telemetry/README` (which are merely lists of raw YouTube URLs).
   - Meanwhile, hidden inside `content/Architecture/OpenTelemetry/` is a 13-document, 180,000-byte, production-grade OpenTelemetry curriculum (`collector.md`, `traces-101.md`, `context-propagation.md`, `exercise-end-to-end.md`) that is completely unreferenced by `Observability.md`!

4. **Resources Directory Link Failure:**
   - `content/index.md` line 34 links to `[[Resources]]`.
   - There is no `content/Resources.md` file; only `content/Resources/` directory.
   - In Quartz, linking to a bare directory without an alias or file creates an ambiguous resolution warning or directory browser rather than a clean landing page.

### 1.2 Directory Links in `AWS.md` and `Security.md`

Wikilinks in Quartz should point to markdown files, not folders. In `content/AWS.md`, **64 links** are written as directory links:

- Example: `| [[AWS/compute/ec2|EC2]] | Virtual machines... |` points to the directory `content/AWS/compute/ec2` instead of `[[AWS/compute/ec2/README|EC2]]`.
- This affects all compute, storage, database, networking, security, monitoring, integration, analytics, and ML entries in `AWS.md`.
- In `content/Security.md`, lines 49–51 link to `[[Security/endpoint-security/hardening]]`, `[[Security/endpoint-security/ids-ips]]`, and `[[Security/endpoint-security/falco]]`, which are **completely empty directories** with 0 files.

### 1.3 Literal `.md` Extensions Inside Wikilinks

In `content/Architecture.md`, lines 41–73 contain 20 wikilinks written with `.md` inside the brackets:

- Example: `[[Architecture/solution-architecture-concepts/foundations/solutions-architecture.md|Solutions Architecture]]`
- Quartz resolves wikilinks against file slugs (which strip `.md`). Writing `.md` causes Quartz to search for `solutions-architecture.md.md`, resulting in dead links across the landing page.

---

## Part 2: Domain-by-Domain Deep Dives

### Domain 1: Kubernetes & EKS (264 Notes)

#### Health Status: 🟢 Exceptional Architecture, Minor Hygiene & Deprecations

- **Strengths:** Outstanding progression from L00 to L09, comprehensive EKS implementation track, hands-on lab playbooks, and CKA/CKAD/CKS certification roadmaps. Reflects Kubernetes baseline up to v1.37.

#### Legitimate Mistakes & Bugs:

1. **67 Files Failing Strict Frontmatter Check:**
   - Running `node scripts/check-k8s-content.mjs --strict` fails with 67 critical errors because files under `content/Kubernetes/concepts/` (e.g., `L03-workloads/04-statefulsets.md`, `L04-services-networking/02-services.md`, `L05-config-storage/01-config-maps.md`, `L06-scheduling-scaling/01-resource-requests-limits.md`, `L07-security/01-api-access/01-authentication-authorization.md`) start directly with `# Heading` without `---` frontmatter.
2. **Raw Stream-of-Consciousness Artifact in Scheduling Gates:**
   - In `content/Kubernetes/concepts/L06-scheduling-scaling/13-scheduling-gates.md`, lines 198–206 contain internal stream-of-consciousness text:
     > _'The Pod is scheduled (because no gate prevents that — wait, yes it does, scheduling gates prevent scheduling). Hmm, let me re-check. Actually, scheduling gates prevent scheduling entirely... Let me re-check the k8s docs. OK — the actual pattern is...'_
     > This should be refactored into authoritative technical prose.
3. **Broken Image Embed in Argo CD Guide:**
   - In `content/Kubernetes/guides/delivery/gitops/argo-cd/README.md:7`: `<figure><img src="../../../../.gitbook/assets/image (33).png" alt=""><figcaption></figcaption></figure>` is completely broken.
4. **Placeholder Values in Gateway API Lab:**
   - In `content/Kubernetes/concepts/L04-services-networking/L09-gateway-api/lab/VERIFY.md:128`: Ships with an unreplaced placeholder string for CA certificates.
5. **Dead Link in Certifications Matrix:**
   - In `content/Kubernetes/certifications/index.md:29`: References `Security hardening labs (P3)` with no link target or markdown implementation.

#### Future Scope & Expansion Opportunities:

1. **Dynamic Resource Allocation (DRA) GA Deep-Dive:** Modern AI/ML workloads on K8s increasingly use DRA with Structured Parameters for NVIDIA/AMD GPUs, vTPUs, and RoCE network devices instead of legacy `resources.limits.nvidia.com/gpu`.
2. **In-Place Pod Vertical Scaling (`resizePolicy`):** Kubernetes GA feature enabling CPU/memory resizing without pod restarts.
3. **ValidatingAdmissionPolicy Deep Dive:** Comprehensive coverage of native Common Expression Language (CEL) admission policies, eliminating webhooks for standard guardrails.
4. **Cilium eBPF & Hubble Architecture Guide:** Upstream K8s networking beyond basic VPC CNI — eBPF socket load balancing, WireGuard transparent encryption, and L7 NetworkPolicies.
5. **Karpenter v1.0+ Production Patterns:** Migration from `Provisioner`/`AWSNodeTemplate` to `NodePool`/`EC2NodeClass`, disruption budgets, and consolidation strategies.

---

### Domain 2: AWS Cloud Architecture (166 Notes)

#### Health Status: 🟠 Asymmetric Structure, Legacy Directory Clutter

- **Strengths:** 30+ service notes in `compute/`, `storage/`, `databases/`, `security/`, `networking/`, and `management-governance/` follow a rigorous standard with CLI snippets, quotas, pricing scenarios, and gotchas.

#### Legitimate Mistakes & Bugs:

1. **The `content/AWS/concepts/` Ghost Directory:**
   - An entire redundant folder `content/AWS/concepts/` contains abandoned stubs that conflict with official sections:
     - `AWS/concepts/iam/README.md` (7 bytes: `# IAM`) vs `AWS/security/iam/README.md` (339 lines of deep content).
     - `AWS/concepts/ebs/README.md` (7 bytes) vs `AWS/storage/ebs/README.md`.
     - `AWS/concepts/s3.md` (214 bytes) vs `AWS/storage/s3/README.md`.
     - `AWS/concepts/iam-1.md` (233 bytes of YouTube links) — accidental duplicate.
     - `AWS/concepts/ecs.md` (421 bytes with 4 broken GitBook image links).
2. **0-Byte Empty File:**
   - `content/AWS/solutions-architect-professional.md` is completely empty (0 bytes).
   - Note: There is an entire 25-note curriculum inside `content/AWS/solutions-architect-professional/` that is never linked by this empty file or by `AWS.md`!
3. **64 Directory-Targeted Wikilinks in `AWS.md`:**
   - `AWS.md` lines 16–161 link to folder paths like `[[AWS/compute/ec2]]`, `[[AWS/storage/s3]]`, `[[AWS/databases/rds]]` instead of their canonical note targets `[[AWS/compute/ec2/README|EC2]]`.
4. **Missing Mention of AWS App Mesh End-of-Life:**
   - In `content/AWS/concepts/app-mesh-vs-vpc-lattice.md`, App Mesh is presented as an active, supported peer to VPC Lattice, omitting that AWS announced App Mesh deprecation with retirement in September 2026.
5. **Raw Bookmark Note:**
   - `content/AWS/blogs.md` contains 3 words and a raw link with no synthesis.

#### Future Scope & Expansion Opportunities:

1. **Merge & Rescue High-Value Notes in `AWS/concepts/`:**
   - `AWS/concepts/magic-ips-169.254.md` (brilliant coverage of link-local IPs, IMDSv2, NTP, VPC DNS) should be moved to `AWS/networking/` or `AWS/compute/ec2/`.
   - `AWS/concepts/cost-management.md` (FinOps, Savings Plans, Compute Optimizer) should be indexed into `AWS.md`.
2. **Amazon VPC Lattice Architecture Guide:** Expand VPC Lattice beyond the comparison note into a full service guide (Service Networks, Service Associations, Auth Policies, Target Groups).
3. **Bedrock & Generative AI on AWS:** Expand beyond the 4-word stub in `AI/aws/bedrock.md` to cover Bedrock Guardrails, Knowledge Bases (RAG), Agents, and Provisioned Throughput.
4. **Index the Solutions Architect Professional (SAP-C02) Track:** Connect the 25 existing notes in `content/AWS/solutions-architect-professional/domain-{1..4}` to the main navigation.

---

### Domain 3: Azure Cloud Platform (49 Notes)

#### Health Status: 🟢 Production-Grade, Uniform & High-Fidelity

- **Strengths:** Pristine 49-file catalog written in September 2026. Zero broken links, zero stubs, comprehensive AKS architecture track (21 deep dives), robust Entra ID and software-defined networking notes.

#### Gaps & Expansion Opportunities:

1. **Missing Modern Azure Cloud-Native Services:**
   - **Azure OpenAI & AI Foundry:** Azure's primary enterprise AI offering is completely absent.
   - **Azure API Management (APIM):** Enterprise API gateway, developer portal, and WAF integration.
   - **Azure Event Grid:** Reactive eventing and CloudEvents broker (only Event Hubs and Service Bus exist).
   - **Microsoft Fabric / Azure Synapse Analytics:** Unified data analytics and lakehouse.
   - **Azure Devops vs GitHub Actions for Azure:** Enterprise deployment strategies.
2. **Dedicated Azure Bastion Deep Dive:** Currently only mentioned briefly inside VM notes.

---

### Domain 4: GCP Cloud Platform (57 Notes)

#### Health Status: 🟢 Production-Grade, Uniform & High-Fidelity

- **Strengths:** 57 meticulously structured notes covering GKE, Cloud Run, Bigtable, Spanner, AlloyDB, BigQuery, Pub/Sub, Dataflow, VPC, and PSC. 0 broken links, 0 stubs.

#### Gaps & Expansion Opportunities:

1. **Missing Core Google Cloud Services:**
   - **Vertex AI:** Google Cloud's flagship AI/ML platform (Model Garden, Gemini API, Search & Conversation, Feature Store).
   - **Cloud Armor:** Enterprise DDoS defense, WAF rule sets (OWASP Top 10), and adaptive rate limiting.
   - **Apigee API Management:** API proxying, API monetization, and security.
   - **Cloud Composer:** Managed Apache Airflow for data workflow orchestration.
   - **Artifact Registry & Cloud Build:** Modern software delivery pipeline on GCP.
   - **GKE Enterprise / Anthos:** Multi-cluster fleet management, Config Sync, and Service Mesh.

---

### Domain 5: Linux, Operating Systems & Kernel (106 Notes)

#### Health Status: 🟡 Rich Internal Catalog, Severely Broken Navigation

- **Strengths:** 106 files with deep technical coverage of kernel subsystems, cgroups, `/proc`, `/sys`, namespaces, systemd, networking tools, and shell scripting.

#### Legitimate Mistakes & Bugs:

1. **Root `Linux.md` Links to 4 Dead Notes:**
   - `content/Linux.md:16` -> `[[Linux/editors]]` (Dead target)
   - `content/Linux.md:19` -> `[[Linux/tools/package-manager]]` (Dead target)
   - `content/Linux.md:20` -> `[[Linux/tools/file-based]]` (Dead target)
   - `content/Linux.md:23` -> `[[Linux/configuration-management-tools]]` (Dead target)
2. **Unwritten Packaging Notes Promised in Packaging README:**
   - In `content/Linux/packaging/README.md`, lines 12–14 link to:
     - `[[Linux/packaging/yum-dnf]]` (Dead target)
     - `[[Linux/packaging/dpkg]]` (Dead target)
     - `[[Linux/packaging/package-repos]]` (Dead target)
   - Only `apt.md` and `pacman.md` exist.
3. **13 Orphaned Linux Notes:**
   - Files like `Linux/concepts/tmpfs.md`, `Linux/concepts/ulimit.md`, `Linux/concepts/tty-pty.md`, `Linux/concepts/sockets.md`, `Linux/networking/ports.md`, `Linux/ssh/ssh-config.md`, and `Linux/tmux.md` have 0 inbound links.

#### Future Scope & Expansion Opportunities:

1. **Modern eBPF & Kernel Tracing:** Deep dive into `bpftrace`, `bcc`, XDP (eXpress Data Path), and kernel tracepoints.
2. **systemd Internals:** Deep dive on D-Bus, socket activation, slice/scope management, and unit file dependency graphing.
3. **Memory Management Internals:** Page cache, anonymous memory, dirty page flushing (`vm.dirty_ratio`), swapiness tuning, and NUMA architecture.
4. **Storage Performance Deep-Dive:** `io_uring` vs `epoll`/AIO, NVMe-oF, and file system tuning (`noatime`, write barriers).

---

### Domain 6: AI, Machine Learning, LLMs & Agentic Systems (49 Notes)

#### Health Status: 🟠 Bifurcated Quality (LangGraph Excellent, Core Concepts Stubs)

- **Strengths:** 24 stellar, highly detailed modules across `content/AI/langchain/` and `content/AI/langgraph/` covering mental models, state reducers, human-in-the-loop, streaming, checkpointers, and testing.

#### Legitimate Mistakes & Incomplete Stubs:

1. **Unindexed LangChain & LangGraph in `AI.md`:**
   - Neither `content/AI/langchain/` nor `content/AI/langgraph/` is listed in the root hub `content/AI.md`!
2. **Severe 1-Line Stubs in Core Topics:**
   - `content/AI/rag.md`: 5 words, containing only 3 YouTube/blog URLs.
   - `content/AI/aws/bedrock.md`: 4 words, containing 1 AWS workshop URL.
   - `content/AI/mlops.md`: 3 words, containing 1 YouTube URL.
   - `content/AI/prompt-injection.md`: 4 words, containing 1 YouTube URL.
   - `content/AI/jobs.md`: 3 words, containing 1 tweet URL.
   - `content/AI/is-saas-dead.md`: 5 words, containing 1 tweet URL.
   - `content/AI/future-with-ai.md`: 7 words, containing 3 YouTube URLs.
3. **Broken Image and PDF Assets:**
   - `AI/ai-ml-genai-whats-the-difference.md`: Broken image `<img src="../.gitbook/assets/image (268).png">`.
   - `AI/inner-workings/phases-in-data-science-process.md`: Broken image `<img src="../../.gitbook/assets/image (269).png">`.
   - `AI/inner-workings/how-chatgpt-came-up.md`: Broken PDF embed `The_Road_to_ChatGPT_An_Informal_Explainer_1678325727.pdf`.
4. **Directory Link in `AI.md`:**
   - `AI.md:28` links to directory `[[AI/aws/sagemaker]]` instead of `[[AI/aws/sagemaker/README|SageMaker]]`.

#### Future Scope & Expansion Opportunities:

1. **Comprehensive RAG Architecture Guide:** Rewrite `AI/rag.md` to cover naive RAG vs advanced RAG, chunking strategies, hybrid search (dense embeddings + BM25 sparse), re-ranking (Cohere/BGE), vector database comparison (Pinecone, Qdrant, Milvus, pgvector), and GraphRAG.
2. **Model Context Protocol (MCP) Deep Dive:** Expand `content/AI/mcp.md` to cover MCP host architecture, server transports (stdio, SSE), tools, resources, prompts, and security boundaries.
3. **Agentic System Patterns:** Multi-agent architectures (Supervisor, Hierarchical, Peer-to-peer), reflection & self-correction, tool execution sandboxes.
4. **Local LLM Serving Stack:** Expand `run-locally/` to cover vLLM (PagedAttention, tensor parallelism), Ollama production deployment, llama.cpp, and quantized formats (GGUF, AWQ, EXL2).
5. **LLM Evaluation & Observability:** TruLens, Ragas, Langfuse, Arize Phoenix, and prompt regression testing.

---

### Domain 7: Software & Solution Architecture (172 Notes)

#### Health Status: 🔴 High Value Mixed with 19 Phantom Modules & 43 Bookmark Stubs

- **Strengths:** Stages 0–2 of Authentication curriculum are phenomenal (~40KB each on crypto primitives, JWT JOSE, OAuth2 PKCE). Foundations, Reliability, and OpenTelemetry contain exceptional notes.

#### Legitimate Mistakes & Phantom Modules:

1. **19 Unwritten Authentication Modules Across Stages 3–6 and Capstone:**
   - The Authentication curriculum outlines 26 modules across 7 stages. Stages 3, 4, 5, 6, and Capstone contain **only empty `README.md` files** linking to 19 non-existent files:
     - **Stage 3 (OIDC):** `01-oidc-fundamentals`, `02-oidc-flows`, `03-claims-and-sub`, `04-discovery-registration`, `05-session-logout` (All 5 missing).
     - **Stage 4 (Federation & SSO):** `01-sso-patterns`, `02-saml-deep-dive`, `03-scim-provisioning`, `04-multi-tenant-b2b-b2c`, `05-idp-vendor-comparison`, `06-b2b-federation` (All 6 missing).
     - **Stage 5 (Security & Attacks):** `01-top-12-attacks`, `02-token-storage`, `03-crypto-hardening`, `04-audit-logging-siem` (All 4 missing).
     - **Stage 6 (HA & Modern Frontier):** `01-ha-identity`, `02-performance-edge`, `03-zero-trust-spiffe`, `04-emerging-standards` (All 4 missing).
     - **Capstone:** `01-keycloak-lab.md` and `02-incident-tabletop.md` (Both missing).
2. **Critical Syntax Errors in OpenTelemetry Notes:**
   - `Architecture/OpenTelemetry/context-propagation.md`: Line 218 has Go code directly after a heading with no opening ` ```go `, and line 223 has a closing ` ``` `. This inverted code fence parity for the entire file (odd fence count: 63), causing 300+ lines of text to be formatted as code! Additionally, lines 79–87 have `||` table header syntax errors.
   - `Architecture/OpenTelemetry/logs-101.md`: Line 437 starts a code block that isn't closed before line 454 (`// LogExporter`), trapping a markdown table inside a code block, followed by another ` ```go ` on line 467 (odd fence count: 51).
   - `Architecture/OpenTelemetry/traces-101.md`: Lines 443–444 use `||` instead of `|`, corrupting table rendering.
3. **Empty Go & Python README Files:**
   - `Architecture/languages/golang/README.md` is 10 bytes: `# Golang\n\n` — contains 0 links to the 16 existing Go notes in that folder!
   - `Architecture/languages/python/README.md` is 10 bytes: `# Python\n\n`.
4. **43 Raw-Link Stubs in Solution Architecture Concepts:**
   - `networking/osi-model.md` (8 words), `networking/tcpip.md` (3 words), `networking/routing.md` (3 words).
   - `protocols/webrtc.md` (3 words), `protocols/server-sent-events.md` (5 words).
   - `performance/rate-limiting.md` (5 words).
   - `software-engineering-concepts/reverse-proxy.md` (5 words), `multi-tenancy.md` (5 words), `api-error-codes.md` (10 words).
   - `system-design/system-design-interviews.md` (5 words).
5. **Broken Image Embeds:**
   - `Architecture/languages/python/decorators.md`: Broken image `<img src="../../.gitbook/assets/image (1)...png">`.
   - `Architecture/solution-architecture-concepts/foundations/solutions-architecture.md`: Broken images `image (66).png` and `image (224).png`.

#### Future Scope & Expansion Opportunities:

1. **Complete Authentication Stages 3–6:** Write the planned 19 modules to complete one of the finest identity curricula in open-source documentation.
2. **Synthesize the 43 Architecture Stubs:** Turn TCP/IP, OSI model, WebRTC, Rate Limiting, and Reverse Proxy notes into full architectural references.
3. **Event-Driven Architecture & Distributed Messaging:** Expand beyond the 4-word stub in `event-driven-architecture/README.md` and 2-word stub in `kafka/README.md` to cover Kafka partition design, consumer groups, exactly-once semantics (EOS), schema registry (Avro/Protobuf), Outbox Pattern, and event sourcing.
4. **API Gateway Design Patterns:** BFF (Backend For Frontend), API composition, canary routing, and edge token translation.

---

### Domain 8: DevOps, CI/CD, GitOps & Platform Engineering (26 Notes)

#### Health Status: 🔴 Highly Asymmetric (DevSecOps Strong, CI/CD Missing)

- **Strengths:** 20 comprehensive modules in `DevOps/devsecops/` covering secure SDLC, threat modeling, SAST, SCA, SBOM, container scanning, cosign artifact signing, and policy as code.

#### Legitimate Mistakes & Bugs:

1. **Missing Core Folders Promised in `DevOps.md`:**
   - `DevOps/ci-cd/README` (Dead target)
   - `DevOps/ci-cd/github-actions` (Dead target)
   - `DevOps/ci-cd/git` (Dead target)
   - `DevOps/devops-sre-platform-engg/README` (Dead target)
2. **Broken Module Links in DevSecOps Mindset:**
   - In `DevOps/devsecops/stage0-foundations/01-devsecops-mindset.md:210-215`, the table uses incorrect shorthand links:
     - `[[M09-container-image-scanning]]` -> Should be `[[09-container-image-scanning]]`
     - `[[M08-dependency-scanning]]` -> Should be `[[07-sca-dependency-scanning]]` (Wrong module number + missing path)
     - `[[M06-secrets-detection]]` -> Should be `[[06-secrets-detection]]`
     - `[[M05-static-analysis-sast]]` -> Should be `[[05-static-analysis-sast]]`
     - `[[M14-supply-chain-attestations]]` -> Should be `[[14-supply-chain-attestations]]`
     - `[[M15-policy-as-code]]` -> Should be `[[15-policy-as-code]]`
     - `[[AI/automation]]` -> Dead target

#### Future Scope & Expansion Opportunities:

1. **Build Out the Missing `DevOps/ci-cd/` Curriculum:**
   - GitHub Actions deep dive: Reusable workflows, composite actions, self-hosted runner security, OIDC federation with cloud providers, matrix builds, cache optimization.
   - GitLab CI / Tekton / Argo Workflows overview.
2. **Platform Engineering & IDP Frameworks:**
   - Backstage architecture: Software catalog, Scaffolder templates, TechDocs.
   - Crossplane vs Terraform for internal developer platforms: Compositions, XRDs, providers.
   - Internal Developer Platforms (IDPs): Humanitec, Port, Kratix.
3. **GitOps Implementation Architecture:**
   - Argo CD & Flux CD comparison, multi-tenant repository layouts (App of Apps vs ApplicationSet), progressive delivery with Argo Rollouts (canary, blue-green, analysis templates).
4. **Infrastructure as Code (IaC) Best Practices:**
   - Terraform / OpenTofu module design, state locking, Terragrunt, drift detection, and automated testing with Terratest.

---

### Domain 9: Security, SIEM & Incident Response (30 Notes)

#### Health Status: 🟠 Deep Wazuh Plan, Sparse Everywhere Else

- **Strengths:** `Security/siem/wazuh/production-plan/README.md` is a 1,203-line enterprise deployment runbook with Terraform, Ansible, and CloudFormation blueprints for 200 agents and 40 AWS accounts.

#### Legitimate Mistakes & Bugs:

1. **16 Broken Wikilinks in Wazuh Production Plan:**
   - In `content/Security/siem/wazuh/production-plan/README.md`, non-markdown files are wrapped in `[[...]]` wikilinks:
     - `[[Security/siem/wazuh/production-plan/cloudformation/iam-roles.yaml]]`
     - `[[Security/siem/wazuh/production-plan/terraform/main.tf]]`
     - `[[Security/siem/wazuh/production-plan/configs/ossec.conf]]`
     - `[[Security/siem/wazuh/production-plan/configs/cloudtrail-rules.xml]]`
     - `[[Security/siem/wazuh/production-plan/configs/linux-rules.xml]]`
     - `[[Security/siem/wazuh/production-plan/ansible/linux-agent.yml]]`
     - `[[Security/siem/wazuh/production-plan/ansible/windows-agent-ssm.json]]`
     - `[[Security/siem/wazuh/production-plan/n8n/wazuh-alert-workflow.json]]`
     - `[[Security/siem/wazuh/production-plan/configs/ilm-policy.json]]`
     - `[[Security/siem/wazuh/production-plan/configs/cloudtrail-decoders.xml]]` (File doesn't exist on disk!)
   - Wrapping raw source code files in wikilinks causes Quartz build failures.
2. **Empty Subdirectories in Endpoint Security:**
   - `Security/endpoint-security/hardening/` (0 files)
   - `Security/endpoint-security/ids-ips/` (0 files)
   - `Security/endpoint-security/falco/` (0 files)
   - `content/Security.md` links directly to these empty directories.
3. **Disjointed Single-File Stubs:**
   - `Security/siem/elastic-security/README.md` and `Security/siem/splunk/README.md` are generic high-level summaries.
   - `Security/cloud-security/aws`, `azure`, `gcp` are single files that do not leverage the deep cloud security notes in the respective AWS/Azure/GCP sections.

#### Future Scope & Expansion Opportunities:

1. **Fill Out Endpoint Security with Falco & eBPF:** Write comprehensive guides for Falco rules, Falco Sidekick, eBPF probes, and threat detection on Linux nodes.
2. **Kubernetes Runtime Defense Integration:** Cross-link `Security/kubernetes-security/` with `Kubernetes/concepts/L07-security/` and `DevOps/devsecops/stage4-runtime/`.
3. **SIEM Threat Detection Engineering:** Add practical detection engineering rules (Sigma rules, YARA rules, Splunk SPL queries, Elasticsearch KQL queries).
4. **Automated Incident Response Playbooks:** Expand `incident-response/playbooks/` with end-to-end incident workflows for credential compromise, ransomware on K8s node, and S3 data exfiltration.

---

### Domain 10: Observability & SRE

#### Health Status: 🔴 Major Structural Reorganization Needed

- **Strengths:** 13 world-class notes in `content/Architecture/OpenTelemetry/` (Collector, Traces, Metrics, Logs, Semantic Conventions, Context Propagation).

#### Legitimate Mistakes & Gaps:

1. **Top-Level Hub Without a Directory:**
   - `content/Observability.md` has no folder `content/Observability/`.
   - It links to `Resources/guides/observability/prometheus` and `open-telemetry` (both bookmark dumps).
   - The real OpenTelemetry curriculum is tucked under `content/Architecture/OpenTelemetry/`.
2. **Prometheus & Grafana Stubs in `Resources/`:**
   - `Resources/guides/observability/prometheus/README.md` (3 lines, YouTube link).
   - `Resources/guides/observability/prometheus/intrumenting.md` (Typo in filename, 5 lines).
   - `Resources/guides/observability/grafana/README.md` (1 line, YouTube link).
   - `Resources/guides/observability/tracing.md` (2 YouTube links).
   - `Resources/guides/observability/ebpf.md` (2 YouTube links).

#### Recommended Restructuring & Expansion:

1. **Elevate Observability to a First-Class Directory:** Create `content/Observability/` and move:
   - `content/Architecture/OpenTelemetry/` -> `content/Observability/opentelemetry/`.
   - Prometheus, Grafana, and Tracing notes from `content/Resources/guides/observability/` -> `content/Observability/`.
2. **Prometheus Architecture Deep Dive:** TSDB internals, WAL, compaction, head block chunk memory, scrape loops, recording rules, alerting rules, and Alertmanager HA clustering.
3. **PromQL Mastery Guide:** Vector matching (`on()`, `ignoring()`, `group_left()`, `group_right()`), rate calculation gotchas (`rate` vs `irate` vs `increase`), histogram quantiles (`histogram_quantile`).
4. **SRE & Reliability Engineering Frameworks:** SLI/SLO/SLA mathematical definitions, error budget burn rate alerting (Google SRE multi-window multi-burn-rate model), and incident retrospective templates.

---

### Domain 11: Resources, Cheat Sheets & Guides (71 Notes)

#### Health Status: 🔴 80% Bookmark Dumps & Legacy Artifacts

- **Strengths:** Covers a broad set of developer interests (system design, networking, testing, databases, wasm, HashiCorp).

#### Legitimate Mistakes & Incomplete Stubs:

1. **57 of 71 Files are Stubs (<80 Words):**
   - 46 files are raw URL dumps containing solely YouTube, blog, or Twitter links with no synthesized notes.
2. **Duplicate OpenTofu Notes:**
   - `content/Resources/guides/open-tofu.md` (76 bytes)
   - `content/Resources/guides/opentofu.md` (75 bytes)
   - Both contain the same YouTube live stream link with slightly different tracking IDs.
3. **Spelling and Formatting Errors:**
   - `content/Resources/system design.md`: File has a space in its filename and no frontmatter.
   - `content/Resources/guides/observability/prometheus/intrumenting.md`: Typo in filename (`intrumenting` instead of `instrumenting`).
   - `content/Resources/guides/wasm/docker-+-wasm.md` and `kubernetes-+-wasm.md`: Plus signs in filenames.
4. **15 Broken GitBook Image/Asset References:**
   - `Resources/cheat-sheets/regex.md`
   - `Resources/guides/platform-engineering/README.md` (3 broken images)
   - `Resources/guides/testing/unit-testing/README.md` (2 broken images)
   - `Resources/guides/testing/unit-testing/test-doubles-mocks-stubs-fakes.md` (4 broken images)
   - `Resources/guides/networking/README.md` (2 broken images)
   - `Resources/guides/observability/README.md` (1 broken image)
   - `Resources/guides/security/zero-trust.md` (1 broken image)
   - `Resources/guides/chatgpt.md` (1 broken PDF link)
   - `Resources/guides/micro-services.md` (1 broken image)

#### Recommended Future Scope:

1. **Transform Raw Links into Executive Summaries:** For key cheat sheets (Linux, Python, System Design), synthesize the external references into high-impact native markdown tables and code snippets.
2. **System Design Primer Integration:** Convert `Resources/system design.md` into a structured curriculum covering scalability principles, back-of-the-envelope calculations, and architectural trade-offs.
3. **Modern IaC Deep Dive:** Merge `open-tofu.md` and `opentofu.md` into a comprehensive OpenTofu guide (state encryption, provider registry, testing).

---

## Part 3: Complete Inventory of Broken Links & Syntax Errors

### 3.1 All 114 Broken Wikilinks (Exact File & Target)

| Source File                                     | Line | Target Link                                     | Issue Type / Diagnostic                 |
| :---------------------------------------------- | :--- | :---------------------------------------------- | :-------------------------------------- |
| `DevOps.md`                                     | 16   | `[[DevOps/ci-cd/github-actions]]`               | Target file does not exist              |
| `DevOps.md`                                     | 17   | `[[DevOps/ci-cd/git]]`                          | Target file does not exist              |
| `DevOps.md`                                     | 23   | `[[DevOps/devops-sre-platform-engg/README]]`    | Target file does not exist              |
| `Linux.md`                                      | 16   | `[[Linux/editors]]`                             | Target file does not exist              |
| `Linux.md`                                      | 19   | `[[Linux/tools/package-manager]]`               | Target file does not exist              |
| `Linux.md`                                      | 20   | `[[Linux/tools/file-based]]`                    | Target file does not exist              |
| `Linux.md`                                      | 23   | `[[Linux/configuration-management-tools]]`      | Target file does not exist              |
| `Linux.md`                                      | 29   | `[[Kubernetes/concepts/networking/networking]]` | Target file does not exist              |
| `Observability.md`                              | 27   | `[[Kubernetes/concepts/networking/networking]]` | Target file does not exist              |
| `Architecture.md`                               | 41   | `[[.../solutions-architecture.md]]`             | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 42   | `[[.../thinking-like-an-architect.md]]`         | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 43   | `[[.../software-planning.md]]`                  | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 47   | `[[.../availability.md]]`                       | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 48   | `[[.../resilience.md]]`                         | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 49   | `[[.../load-balancing.md]]`                     | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 50   | `[[.../idempotency.md]]`                        | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 53   | `[[.../caching.md]]`                            | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 54   | `[[.../rate-limiting.md]]`                      | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 55   | `[[.../percentile.md]]`                         | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 56   | `[[.../performance-testing.md]]`                | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 59   | `[[.../security.md]]`                           | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 60   | `[[.../shift-left.md]]`                         | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 61   | `[[.../totp.md]]`                               | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 64   | `[[.../cheatsheets.md]]`                        | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 65   | `[[.../cap-theorem.md]]`                        | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 66   | `[[.../concurrency.md]]`                        | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 67   | `[[.../stateful-vs-stateless.md]]`              | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 68   | `[[.../12-factor-app.md]]`                      | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 72   | `[[.../hashing.md]]`                            | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 73   | `[[.../cdn.md]]`                                | Contains `.md` inside wikilink target   |
| `Architecture.md`                               | 89   | `[[Kubernetes/concepts/networking/networking]]` | Target file does not exist              |
| `Architecture.md`                               | 90   | `[[databases]]`                                 | Target file does not exist              |
| `DevOps/.../01-devsecops-mindset.md`            | 210  | `[[M09-container-image-scanning]]`              | Missing prefix/path to module 09        |
| `DevOps/.../01-devsecops-mindset.md`            | 210  | `[[M08-dependency-scanning]]`                   | Missing prefix/path to module 07        |
| `DevOps/.../01-devsecops-mindset.md`            | 211  | `[[M06-secrets-detection]]`                     | Missing prefix/path to module 06        |
| `DevOps/.../01-devsecops-mindset.md`            | 212  | `[[M05-static-analysis-sast]]`                  | Missing prefix/path to module 05        |
| `DevOps/.../01-devsecops-mindset.md`            | 213  | `[[M14-supply-chain-attestations]]`             | Missing prefix/path to module 14        |
| `DevOps/.../01-devsecops-mindset.md`            | 215  | `[[M15-policy-as-code]]`                        | Missing prefix/path to module 15        |
| `DevOps/.../01-devsecops-mindset.md`            | 216  | `[[AI/automation]]`                             | Target file does not exist              |
| `Linux/packaging/README.md`                     | 12   | `[[Linux/packaging/yum-dnf]]`                   | Unwritten module                        |
| `Linux/packaging/README.md`                     | 13   | `[[Linux/packaging/dpkg]]`                      | Unwritten module                        |
| `Linux/packaging/README.md`                     | 14   | `[[Linux/packaging/package-repos]]`             | Unwritten module                        |
| `Security/siem/wazuh/production-plan/README.md` | 658  | `[[.../iam-roles.yaml]]`                        | Wikilink pointing to raw YAML config    |
| `Security/siem/wazuh/production-plan/README.md` | 710  | `[[.../cloudtrail-decoders.xml]]`               | Target XML file missing                 |
| `Security/siem/wazuh/production-plan/README.md` | 856  | `[[.../linux-agent.yml]]`                       | Wikilink pointing to raw Ansible YAML   |
| `Security/siem/wazuh/production-plan/README.md` | 868  | `[[.../windows-agent-ssm.json]]`                | Wikilink pointing to raw JSON config    |
| `Security/siem/wazuh/production-plan/README.md` | 974  | `[[.../wazuh-alert-workflow.json]]`             | Wikilink pointing to raw n8n JSON       |
| `Security/siem/wazuh/production-plan/README.md` | 1048 | `[[.../cloudtrail-rules.xml]]`                  | Wikilink pointing to raw XML config     |
| `Security/siem/wazuh/production-plan/README.md` | 1062 | `[[.../linux-rules.xml]]`                       | Wikilink pointing to raw XML config     |
| `Security/siem/wazuh/production-plan/README.md` | 1195 | `[[.../terraform/main.tf]]`                     | Wikilink pointing to raw Terraform file |
| `Security/siem/wazuh/production-plan/README.md` | 1196 | `[[.../configs/ossec.conf]]`                    | Wikilink pointing to raw config file    |
| `Security/siem/wazuh/production-plan/README.md` | 1202 | `[[.../configs/ilm-policy.json]]`               | Wikilink pointing to raw JSON file      |
| `Architecture/.../stage2/README.md`             | 15   | `[[05-introspection-revocation]]`               | Unwritten module in Auth Stage 2        |
| `Architecture/.../stage2/README.md`             | 16   | `[[06-oauth-2-1]]`                              | Unwritten module in Auth Stage 2        |
| `Architecture/.../stage3/README.md`             | 18   | `[[01-oidc-fundamentals]]`                      | Unwritten module in Auth Stage 3        |
| `Architecture/.../stage3/README.md`             | 19   | `[[02-oidc-flows]]`                             | Unwritten module in Auth Stage 3        |
| `Architecture/.../stage3/README.md`             | 20   | `[[03-claims-and-sub]]`                         | Unwritten module in Auth Stage 3        |
| `Architecture/.../stage3/README.md`             | 21   | `[[04-discovery-registration]]`                 | Unwritten module in Auth Stage 3        |
| `Architecture/.../stage3/README.md`             | 22   | `[[05-session-logout]]`                         | Unwritten module in Auth Stage 3        |
| `Architecture/.../stage4/README.md`             | 18   | `[[01-sso-patterns]]`                           | Unwritten module in Auth Stage 4        |
| `Architecture/.../stage4/README.md`             | 19   | `[[02-saml-deep-dive]]`                         | Unwritten module in Auth Stage 4        |
| `Architecture/.../stage4/README.md`             | 20   | `[[03-scim-provisioning]]`                      | Unwritten module in Auth Stage 4        |
| `Architecture/.../stage4/README.md`             | 21   | `[[04-multi-tenant-b2b-b2c]]`                   | Unwritten module in Auth Stage 4        |
| `Architecture/.../stage4/README.md`             | 22   | `[[05-idp-vendor-comparison]]`                  | Unwritten module in Auth Stage 4        |
| `Architecture/.../stage4/README.md`             | 23   | `[[06-b2b-federation]]`                         | Unwritten module in Auth Stage 4        |
| `Architecture/.../stage5/README.md`             | 18   | `[[01-top-12-attacks]]`                         | Unwritten module in Auth Stage 5        |
| `Architecture/.../stage5/README.md`             | 19   | `[[02-token-storage]]`                          | Unwritten module in Auth Stage 5        |
| `Architecture/.../stage5/README.md`             | 20   | `[[03-crypto-hardening]]`                       | Unwritten module in Auth Stage 5        |
| `Architecture/.../stage5/README.md`             | 21   | `[[04-audit-logging-siem]]`                     | Unwritten module in Auth Stage 5        |
| `Architecture/.../stage6/README.md`             | 18   | `[[01-ha-identity]]`                            | Unwritten module in Auth Stage 6        |
| `Architecture/.../stage6/README.md`             | 19   | `[[02-performance-edge]]`                       | Unwritten module in Auth Stage 6        |
| `Architecture/.../stage6/README.md`             | 20   | `[[03-zero-trust-spiffe]]`                      | Unwritten module in Auth Stage 6        |
| `Architecture/.../stage6/README.md`             | 21   | `[[04-emerging-standards]]`                     | Unwritten module in Auth Stage 6        |
| `Architecture/.../capstone/README.md`           | 59   | `[[01-keycloak-lab]]`                           | Unwritten Capstone module               |
| `Architecture/.../capstone/README.md`           | 60   | `[[02-incident-tabletop]]`                      | Unwritten Capstone module               |

### 3.2 All 25 Broken GitBook Image & Media References

| Source File                                           | Line | Broken Image / Asset Path                    | Recommended Replacement                                                |
| :---------------------------------------------------- | :--- | :------------------------------------------- | :--------------------------------------------------------------------- |
| `AI/ai-ml-genai-whats-the-difference.md`              | 3    | `../.gitbook/assets/image (268).png`         | Native Mermaid diagram (AI vs ML vs DL vs GenAI Venn)                  |
| `AI/inner-workings/phases-in-data-science-process.md` | 3    | `../../.gitbook/assets/image (269).png`      | Native Mermaid flowchart (CRISP-DM lifecycle)                          |
| `AI/inner-workings/how-chatgpt-came-up.md`            | 5    | `The_Road_to_ChatGPT_...pdf`                 | Synthesized markdown timeline & transformer paper references           |
| `AWS/concepts/ecs.md`                                 | 5    | `../../.gitbook/assets/running-your-app.png` | Native Mermaid flowchart (ECS Task Definition -> Service -> Task)      |
| `AWS/concepts/ecs.md`                                 | 9    | `../../.gitbook/assets/scaling.png`          | Native Mermaid diagram (ECS Service Auto Scaling & Capacity Providers) |
| `AWS/concepts/ecs.md`                                 | 13   | `../../.gitbook/assets/security.png`         | Native diagram (Task Execution Role vs Task Role)                      |
| `AWS/concepts/ecs.md`                                 | 17   | `../../.gitbook/assets/ecsflow.png`          | Native sequence diagram (ECR pull -> container start)                  |
| `Kubernetes/guides/delivery/gitops/argo-cd/README.md` | 7    | `../../../../.gitbook/assets/image (33).png` | Native Mermaid flowchart (Git repo -> Argo CD controller -> K8s API)   |
| `Architecture/languages/python/decorators.md`         | 5    | `../../.gitbook/assets/image (1)...png`      | Clean Python code block demonstrating closure execution order          |
| `Architecture/.../solutions-architecture.md`          | 17   | `../.gitbook/assets/image (66).png`          | Native Mermaid diagram (Architect vs Engineer responsibilities)        |
| `Architecture/.../solutions-architecture.md`          | 46   | `../.gitbook/assets/image (224).png`         | Native NFR evaluation matrix table                                     |
| `Resources/cheat-sheets/regex.md`                     | 3    | `../.gitbook/assets/image (3)...png`         | Comprehensive Regex cheatsheet table                                   |
| `Resources/guides/micro-services.md`                  | 5    | `../.gitbook/assets/image (12).png`          | Native Mermaid diagram (Monolith decomposition patterns)               |
| `Resources/guides/platform-engineering/README.md`     | 7    | `../../.gitbook/assets/image (14).png`       | Native Mermaid diagram (Platform engineering mental model)             |
| `Resources/guides/platform-engineering/README.md`     | 9    | `../../.gitbook/assets/image (222).png`      | Native diagram (Developer portal vs K8s control plane)                 |
| `Resources/guides/platform-engineering/README.md`     | 31   | `../../.gitbook/assets/image (37).png`       | Native diagram (Thinnest Viable Platform)                              |
| `Resources/guides/networking/README.md`               | 7    | `../../.gitbook/assets/image (2)...png`      | Native OSI vs TCP/IP comparison table                                  |
| `Resources/guides/networking/README.md`               | 9    | `../../.gitbook/assets/image (1)...png`      | Native packet encapsulation flowchart                                  |
| `Resources/guides/observability/README.md`            | 9    | `../../.gitbook/assets/image (1)...png`      | Native 3 Pillars Venn diagram (Metrics, Logs, Traces)                  |
| `Resources/guides/security/zero-trust.md`             | 5    | `../../.gitbook/assets/image (236).png`      | Native Zero Trust architecture diagram (Never trust, verify always)    |
| `Resources/guides/chatgpt.md`                         | 5    | `The_Road_to_ChatGPT_...pdf`                 | Clean markdown summary of instruction tuning & RLHF                    |
| `Resources/guides/testing/unit-testing/README.md`     | 3    | `../../../.gitbook/assets/image (252).png`   | Testing pyramid diagram (Unit, Integration, E2E)                       |
| `Resources/guides/testing/unit-testing/README.md`     | 5    | `../../../.gitbook/assets/image (251).png`   | Testing diamond diagram                                                |
| `Resources/guides/testing/.../test-doubles-...md`     | 5    | `image (253).png` to `image (256).png`       | Code comparison table showing Dummy vs Stub vs Spy vs Mock vs Fake     |

### 3.3 Code Fence Inversions & Table Syntax Errors

1. **`Architecture/OpenTelemetry/context-propagation.md` (Line 218):**
   - Missing opening ` ```go ` before line 219. Closing fence ` ``` ` on line 223 flips the markdown state.
   - Odd total count of 63 code fences flips all subsequent text blocks into code.
   - Lines 79–87 use `||` instead of `|`, breaking table rendering.
2. **`Architecture/OpenTelemetry/logs-101.md` (Line 454):**
   - Missing closing ` ``` ` after line 452. Lines 454–466 (text and table) are trapped inside a code fence started on line 437.
   - Line 467 opens another ` ```go `, causing an odd total count of 51 code fences.
3. **`Architecture/OpenTelemetry/traces-101.md` (Lines 443–444):**
   - Table header uses double pipe `|| Sampler | When to use | Gotcha |` and `||---|---|---|` instead of single pipe `|`.

---

## Part 4: Strategic Action Plan & Content Expansion Roadmap

### Phase 1: High-Priority Mechanical Fixes (Zero Content Risk)

1. **Fix Code Fence & Table Syntax Errors:**
   - Add missing ` ```go ` at line 218 in `Architecture/OpenTelemetry/context-propagation.md` and replace `||` with `|`.
   - Add closing ` ``` ` at line 453 in `Architecture/OpenTelemetry/logs-101.md`.
   - Fix table header pipes in `Architecture/OpenTelemetry/traces-101.md`.
2. **Resolve Literal `.md` in Wikilinks:**
   - Strip `.md` from all 20 wikilinks in `content/Architecture.md` so Quartz correctly resolves them to existing notes.
3. **Fix Shorthand Module Links in DevSecOps:**
   - In `content/DevOps/devsecops/stage0-foundations/01-devsecops-mindset.md`, update `[[M09-...]]` to `[[09-container-image-scanning]]` and canonical relative paths.
4. **Convert Wazuh Config Wikilinks to Standard Markdown Links:**
   - In `content/Security/siem/wazuh/production-plan/README.md`, change `[[.../main.tf]]` to standard relative links `[main.tf](./terraform/main.tf)` so Quartz does not treat raw code files as wiki pages.
5. **Clean Up Broken Images & Filename Typos:**
   - Remove broken `<figure><img src="...gitbook...">` tags and replace with structured text or Mermaid diagrams.
   - Rename `Resources/system design.md` to `Resources/system-design.md` (remove space).
   - Rename `Resources/guides/observability/prometheus/intrumenting.md` to `instrumenting.md`.
   - Delete redundant duplicate `Resources/guides/open-tofu.md` in favor of `opentofu.md`.
   - Add standard YAML frontmatter to the 67 Kubernetes notes currently failing strict validation.

### Phase 2: Architectural & Navigational Realignment

1. **Synchronize Root Hub Pages with Directory Realities:**
   - Overwrite outdated `content/Linux.md` with the comprehensive, validated content from `content/Linux/README.md`.
   - Update `content/AWS.md` to replace all 64 directory links (`[[AWS/compute/ec2]]`) with canonical targets (`[[AWS/compute/ec2/README|EC2]]`).
   - Create `content/Resources.md` to cleanly land users exploring `[[Resources]]` from the homepage.
   - Link `content/AWS/solutions-architect-professional/` into `AWS.md` and delete the empty 0-byte file.
2. **Consolidate the Observability Ecosystem:**
   - Create a dedicated `content/Observability/` top-level directory.
   - Relocate `content/Architecture/OpenTelemetry/` into `content/Observability/opentelemetry/`.
   - Relocate Prometheus, Grafana, and Tracing notes from `content/Resources/guides/observability/` into `content/Observability/`.
   - Update `content/Observability.md` to serve as a world-class landing hub.
3. **Prune and Rescue `content/AWS/concepts/`:**
   - Delete empty stubs (`iam/README.md`, `ebs/README.md`, `api-gateway/README.md`, `iam-1.md`).
   - Rescue high-value notes (`magic-ips-169.254.md`, `cost-management.md`) by moving them into the appropriate `AWS/networking/` and `AWS/management-governance/` folders.

### Phase 3: High-Impact Content Expansion Roadmap

1. **Complete the 19 Missing Authentication Curriculum Modules:**
   - Write the missing Stage 3 (OIDC 01–05), Stage 4 (SAML/SSO/SCIM 01–06), Stage 5 (Security 01–04), Stage 6 (HA & Frontier 01–04), and Capstone (Keycloak reference lab & tabletop) notes following the gold standard established in Stages 0–2.
2. **Build the Missing DevOps Hubs:**
   - Create `content/DevOps/ci-cd/` with production-grade GitHub Actions, GitLab CI, and reusable workflow notes.
   - Create `content/DevOps/platform-engineering/` covering Internal Developer Platforms, Backstage, and Crossplane.
   - Create `content/DevOps/gitops/` covering Argo CD ApplicationSets, sync waves, and progressive delivery.
3. **Transform AI Bookmark Notes into First-Class Deep Dives:**
   - Index `AI/langchain/` and `AI/langgraph/` directly into `content/AI.md`.
   - Rewrite `AI/rag.md` from 5 words into a definitive guide to RAG architectures (vector search, chunking, hybrid retrieval, re-ranking).
   - Expand `AI/mcp.md` (Model Context Protocol) and `AI/run-locally/` (vLLM, Ollama, GGUF/AWQ).
   - Write a dedicated AWS Bedrock service guide.
4. **Synthesize the 43 Architecture & 46 Resource Bookmark Notes:**
   - Replace raw external links in OSI model, TCP/IP, WebRTC, Rate Limiting, and Reverse Proxy with native architectural diagrams and production best practices.
5. **Expand Cloud-Native Kubernetes & Cloud Ecosystems:**
   - Kubernetes: eBPF/Cilium networking, Dynamic Resource Allocation (DRA) for GPUs, ValidatingAdmissionPolicies (CEL), in-place pod vertical scaling.
   - Azure: Azure OpenAI / AI Foundry, Event Grid, API Management.
   - GCP: Vertex AI, Cloud Armor, Apigee, Cloud Composer.

---

_End of Audit Report. Generated locally for Darshan's CloudNative Wiki._
