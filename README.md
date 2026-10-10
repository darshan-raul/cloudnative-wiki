# CloudNative Wiki

Personal knowledge graph covering AWS, Kubernetes, Linux, AI, DevOps, and more.

Built with [Quartz v4](https://quartz.jzhao.xyz) — a static site generator for digital gardens.

## Quick Start

```bash
# Install dependencies
npm install

# Development server with live reload (http://localhost:3009)
npm run docs

# Production build
npm run quartz build

# Check for lint/type issues
npm run check

# Auto-format all files
npm run format
```

## Commands

| Command                 | Description                                      |
| ----------------------- | ------------------------------------------------ |
| `npm run docs`          | Dev server with live reload (port 3009)          |
| `npm run quartz build`  | Full production build to `public/`               |
| `npm run check`         | TypeScript, content validation, Prettier         |
| `npm run format`        | Auto-format all files with Prettier              |
| `npm run check:content` | Validate every note: links, frontmatter, orphans |
| `npm run test`          | Run tsx test suite, then content validation      |
| `npm run profile`       | Profile build performance                        |

## Content Structure

```
content/
├── AWS.md            ☁️  Amazon Web Services
├── Azure.md          🔷  Microsoft Azure
├── GCP.md            🟠  Google Cloud
├── Kubernetes.md     ☸️  Container orchestration, EKS track
├── Containers.md     📦  Images, registries, runtimes
├── Linux.md          🐧  System administration
├── DevOps.md         🚀  CI/CD, IaC, SRE, DevSecOps, platform engineering
├── Observability.md  📊  Metrics, logs, traces, OpenTelemetry
├── Architecture.md   🏛️  System design, databases, authentication
├── Security.md       🔐  SIEM, zero trust, incident response
├── AI.md             🤖  LLMs, agents, RAG, evals
└── index.md          Main hub
```

## Notes

- **Node >= 22** required
- Content lives in `content/` (Obsidian vault)
- Build output in `public/`
- Framework code in `quartz/` (don't edit unless maintaining Quartz)
- Working documents (plans, trackers, audits) live in `planning/` and are not published
