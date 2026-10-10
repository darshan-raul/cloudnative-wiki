# solution-architecture-concepts — Reorganization Plan

**Date:** 2025-05-24
**Status:** Approved for execution

## Goal

Fix all stubs, unlinked subdirs, and broken references in `solution-architecture-concepts/`. Restructure into logical groupings that reflect how a solution architect actually navigates this content.

---

## Final Subdirectory Structure

```
solution-architecture-concepts/
│
├── README.md                    ← Hub: overview of entire section
│
├── foundations/                 ← Core architect mindset
│   ├── thinking-like-an-architect.md
│   ├── solutions-architecture.md
│   ├── software-planning.md
│   ├── non-functional-requirements/
│   │   ├── README.md
│   │   ├── back-of-the-envelope-calculations.md
│   │   ├── reliability-vs-availability.md
│   │   └── scaling.md
│   └── high-cohesion-loose-coupling.md
│
├── reliability/                 ← Operational resilience
│   ├── availability.md
│   ├── resilience.md
│   ├── idempotency.md
│   ├── load-balancing.md
│   └── memory-leaks.md
│
├── performance/                 ← Performance& scaling
│   ├── README.md
│   ├── caching.md
│   ├── rate-limiting.md
│   ├── percentile.md
│   ├── performance-testing.md
│   └── memory-leaks.md          ← (moved from root)
│
├── security/                    ← Security patterns
│   ├── security.md
│   ├── shift-left.md
│   └── totp.md
│
├── architecture-patterns/        ← Structural patterns (was: architecture/)
│   ├── README.md
│   └── architecture-patterns.md
│
├── system-design/               ← System design
│   ├── README.md
│   └── system-design-interviews.md
│
├── protocols/                   ← Network protocols
│   ├── README.md
│   ├── http/
│   ├── websocket.md
│   ├── server-sent-events.md
│   └── webrtc.md
│
├── api-design/                  ← API design & contracts
│   ├── cheatsheets.md
│   ├── concurrency.md
│   ├── cap-theorem.md
│   ├── stateful-vs-stateless.md
│   ├── 12-factor-app.md
│   └── api-error-codes.md
│
├── data-architecture/           ← Data decisions
│   ├── bson.md
│   ├── base64-encoding.md
│   ├── hashing.md
│   ├── cdn.md
│   └── databases/
│       ├── README.md
│       ├── postgres/
│       ├── mongodb/
│       ├── normalization.md
│       ├── indexing.md
│       ├── database-schema-design.md
│       ├── foreign-keys-and-constraints.md
│       └── opm-or-not-to-orm.md
│
├── authentication/              ← Auth patterns (exists, keep)
│   ├── README.md
│   ├── oauth2.md
│   ├── oidc.md
│   ├── saml.md
│   └── jwt/
│
├── event-driven-architecture/   ← Async messaging (exists, keep)
│   ├── README.md
│   ├── kafka/
│   └── rabbitmq.md
│
├── networking/                  ← Networking (exists, keep)
│   ├── README.md
│   ├── osi-model.md
│   ├── tcpip.md
│   ├── dns-over-https.md
│   ├── nat.md
│   └── routing.md
│
├── cluster-management/          ← Consensus protocols (exists, keep)
│   ├── README.md
│   ├── raft.md
│   └── gossip-protocol.md
│
├── cryptography/               ← Crypto (was: openssl/)
│   ├── README.md
│   ├── pki.md
│   ├── keystore.md
│   └── signing-and-verifying.md
│
└── developer-tooling/          ← Dev tooling (was: vscode/)
    ├── README.md
    └── breakpoints.md
```

---

## Actions

### Stubs Fixed (this session)

- [x] 12-factor-app.md — written
- [x] cheatsheets.md — written
- [x] idempotency.md — written
- [x] memory-leaks.md — written
- [x] security.md — written
- [x] shift-left.md — written
- [x] software-planning.md — written
- [x] thinking-like-an-architect.md — written
- [x] availability.md — written (was stub with GitBook images)
- [x] basics.md — written (was stub with GitBook images)
- [x] caching.md — written (was stub with GitBook images)
- [x] load-balancing.md — written (was stub with GitBook images)
- [x] resilience.md — written (was stub with GitBook images)
- [x] cap-theorem.md — written (was stub)
- [x] concurrency.md — written (was stub)
- [x] performance-testing.md — written (was stub)

### Directory Renames

- [x] `architecture/` → `architecture-patterns/`
- [x] `openssl/` → `cryptography/`
- [x] `vscode/` → `developer-tooling/`

### File Moves

- [x] `databases/` → `data-architecture/databases/`
- [x] `performance/memory-leaks.md` ← (moved from root to reliability/)
- [x] Root-level files consolidated into new grouping dirs

### Duplicate Removal

- [x] `software-engineering-concepts/base64-encoding.md` — deleted
- [x] `software-engineering-concepts/basics.md` — deleted
- [x] `software-engineering-concepts/cache.md` — deleted

### GitBook Image Refs — Fix or Remove

- [x] `architecture-patterns/README.md` — GitBook image refs replaced
- [x] `architecture-patterns/architecture-patterns.md` — GitBook image refs replaced
- [x] `authentication/jwt/README.md` — GitBook image refs replaced
- [x] `authentication/oauth2.md` — GitBook image refs replaced
- [x] `networking/osi-model.md` — GitBook image refs replaced
- [x] `software-engineering-concepts/README.md` — GitBook image refs replaced
- [x] `software-engineering-concepts/api-error-codes.md` — GitBook image refs replaced
- [x] `software-engineering-concepts/https.md` — GitBook image refs replaced

### Section READMEs Created

- [x] `foundations/README.md`
- [x] `reliability/README.md`
- [x] `security/README.md`
- [x] `api-design/README.md`
- [x] `data-architecture/README.md`
- [x] `architecture-patterns/README.md`
- [x] `cryptography/README.md`
- [x] `developer-tooling/README.md`

### Hub Update

- [x] `Architecture.md` — added links to all new groupings (foundations, reliability, security, api-design, data-architecture, architecture-patterns, cryptography, developer-tooling)

### Build Verification

- [x] `npx quartz build` passes
