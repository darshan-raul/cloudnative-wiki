---
name: obsidian-vault-research
description: Use when user asks to research a topic and add documentation to the Obsidian vault, create docs for a tool or concept, update vault content based on web research, or perform any topic research that results in vault documentation. Handles all subjects (k8s, devops, security, etc).
---

# Obsidian Vault Research Skill

Researches topics and creates/updates documentation in the Obsidian vault.

## Vault Location
- Root: `/home/darshan/projects/cloudnative-wiki/content`
- Structure follows content organization (see below)

## Vault Structure

```
content/
├── Kubernetes/guides/      # K8s tools, workflows, guides
├── Kubernetes/concepts/   # K8s concepts
├── AWS/, GCP/, Azure/     # Cloud platforms
├── Security.md, DevOps.md # Top-level topic docs
└── index.md               # Entry point
```

## Workflow

1. **Analyze request** - Identify the topic, appropriate location, and scope
2. **Web research** - Fetch official docs, GitHub, tutorials relevant to topic
3. **Determine file path**:
   - K8s tools/guides → `Kubernetes/guides/<tool>.md`
   - K8s concepts → `Kubernetes/concepts/<topic>.md`
   - Cloud → `<cloud>/<topic>.md`
   - General → `<topic>.md` or in relevant section
4. **Check existing docs** - Read current content to avoid duplication
5. **Create/update document** with:
   - YAML frontmatter: `title`, `tags`, `date`, `description`
   - Clear structure with `##` sections
   - Tables for CLI flags/keybindings
   - Code blocks for examples
   - `[Official Docs](url)` link early
   - `## References` at end
6. **Update index** - Add to appropriate `README.md` if new file

## Document Template

```markdown
---
title: <Tool/Topic Name>
tags: [<category>]
date: <YYYY-MM-DD>
description: <One-line description>
---

# <Tool/Topic Name>

[<Description>](official-url)

## Overview

## Installation

## <Main Sections...>

## References
```

## Index Update Pattern

For new `Kubernetes/guides/<tool>.md`, add to `Kubernetes/guides/README.md`:
```markdown
- [[<tool>]] - <brief description>
```

## Research Sources Priority

1. Official documentation site
2. GitHub README/source
3. Official blog/tutorials
4. Community tutorials (authenticated sources only if reliable)

## Verification

- Confirm file written
- Confirm index updated (if new)
- Report file path and summary