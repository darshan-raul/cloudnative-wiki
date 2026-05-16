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

| Command | Description |
|---------|-------------|
| `npm run docs` | Dev server with live reload (default port 3009) |
| `npm run quartz build` | Full production build to `public/` |
| `npm run check` | TypeScript check + Prettier formatting |
| `npm run format` | Auto-format all files with Prettier |
| `npm run test` | Run tsx test suite |
| `npm run profile` | Profile build performance |

## Content Structure

```
content/
├── AWS.md           ☁️  Amazon Web Services
├── Kubernetes.md    ☸️  Container orchestration
├── Linux.md         🐧  System administration
├── AI.md            🤖  ML, GenAI, LLMs
├── DevOps.md        🚀  CI/CD, DevSecOps
├── Architecture.md  🏛️  System design
├── Azure.md         Microsoft Azure
├── GCP.md           Google Cloud
└── index.md         Main hub
```

## Notes

- **Node >= 22** required
- Content lives in `content/` (Obsidian vault)
- Build output in `public/`
- Framework code in `quartz/` (don't edit unless maintaining Quartz)