# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal cloud-native knowledge wiki (~970 markdown notes) published as a static site with **Quartz v4**. Two very different kinds of work happen here:

1. **Content work** (the vast majority) — writing and restructuring notes in `content/`, which is also an Obsidian vault.
2. **Framework work** (rare) — `quartz/` is a vendored copy of upstream Quartz 4.5.2 with a few local patches. Leave it alone unless the task is specifically about site behaviour.

## Commands

```bash
npm run docs                          # dev server with live reload on http://localhost:3009
npm run quartz build                  # production build into public/
npm run check                         # tsc --noEmit + check:content + prettier --check
npm run check:content                 # content validator only (fast, no build)
npm run format                        # prettier --write (formats markdown in content/ too)
npm run test                          # tsx --test, then check:content
npx tsx --test quartz/util/path.test.ts   # run a single test file
```

- Node >= 22. Tests use the Node test runner through `tsx` (no jest/vitest).
- Prettier runs over markdown, so run `npm run format` after editing notes or `npm run check` fails. Tables get re-aligned by it — don't hand-align them.

## The content validator

`scripts/check-content.mjs` validates **every note in `content/`** and fails `npm run check` and `npm run test`. Run it after any content change.

```bash
node scripts/check-content.mjs                # whole vault
node scripts/check-content.mjs Kubernetes AWS # report only on these top-level paths
node scripts/check-content.mjs --verbose      # also list warnings (stub notes)
```

It fails on:

- missing frontmatter, or a missing `title`, `tags`, `date` or `description`;
- no `# H1` (drafts excepted), an unclosed code fence, or a table row starting with `||`;
- a wikilink that is broken, points at a directory, or is **ambiguous** (a bare basename that matches more than one note);
- a wikilink alias inside a table without an escaped pipe;
- an **orphan**: a note that no other note links to.

## Content architecture

`content/` has eleven domains: `AWS`, `Azure`, `GCP`, `Kubernetes`, `Containers`, `Linux`, `DevOps`, `Observability`, `Architecture`, `Security`, `AI`. `content/index.md` is the home page and links to each domain hub.

### Hub pages and folder notes

Each domain has a root hub file **next to** its folder (`content/Kubernetes.md` + `content/Kubernetes/`). A local patch (`getFolderNotes` in `quartz/util/path.ts`) gives such a file the slug `<folder>/index`, so it becomes the folder's landing page — unless the folder already contains its own `index.md`, which wins.

Inside folders, section indexes are inconsistent by history: mostly `README.md`, sometimes `index.md`, and `00-README.md` inside the Kubernetes `L0x` levels. Match whatever the surrounding folder already uses. **When adding a note, add it to that folder's index** — otherwise it is an orphan and the validator fails.

### Where things live (non-obvious placements)

- `Observability/opentelemetry/` holds the OpenTelemetry curriculum (it used to be under Architecture).
- Databases, Redis, Kafka and event-driven design are under `Architecture/solution-architecture-concepts/` (`data-architecture/databases/`, `event-driven-architecture/`).
- Infrastructure as code, SRE and platform engineering are under `DevOps/`.
- Namespaces, cgroups and other kernel primitives stay in `Linux/`; `Containers/` covers images, registries, runtimes and links back to them.
- EKS lives under `Kubernetes/eks/`, not under `AWS/`.
- Bookmarks do not get their own notes. Put external links in a `## Further reading` section of the note on that topic.

### Links

- Use Obsidian wikilinks with full paths from the content root and a display alias: `[[Kubernetes/concepts/00-hub|Concepts Hub]]`. Inside a table, escape the pipe: `[[path\|Alias]]`.
- Link resolution is `shortest` (`CrawlLinks` in `quartz.config.ts`), so a bare `[[note-name]]` works only while the basename is unique. Many basenames (`README`, `index`, `troubleshooting`, `security`) are not, and the validator rejects ambiguous ones.
- Always link to a markdown page, never to a bare directory.
- Link across domains where topics meet (an EKS note to the AWS IAM note, a Kubernetes networking note to the Linux one). Many notes end with an `## Across the wiki` section for this.

### Frontmatter

Every note starts with `title`, `tags`, `date` (YYYY-MM-DD), `description`; optional `aliases` and `draft`. Quote any `description` containing a colon or em-dash — unquoted ones have broken YAML parsing before. Every non-draft note needs one `# H1`. `draft: true` removes a note from the build (`RemoveDrafts`); `private/` and `templates/` folders are ignored.

### Kubernetes is the most structured domain

- `concepts/L00-start-here` … `L09-advanced` — a sequential curriculum with numbered notes (`03-deployments.md`), each level indexed by `00-README.md`, all rooted at `concepts/00-hub.md`.
- `guides/` (`tools`, `networking`, `delivery`, `non-functional`, `troubleshooting`), `eks/`, `review/` (refreshers, decision tables), `certifications/`.
- `labs/00`–`09` are cumulative: they share one `kind` cluster (`labs/kind-config.yaml`, cluster name `kind-k8s-labs`) and one workload (`podinfo`).
- `MAINTENANCE.md` is the playbook for syncing to a new upstream Kubernetes minor release. The curriculum declares a version baseline (currently 1.37) in `content/Kubernetes.md` and `concepts/00-hub.md`; keep new notes consistent with it and update `updates-along-the-versions.md` when it moves.

## Working documents

Plans, progress trackers and audits live in `planning/` at the repo root, outside `content/`, so they are not published. Do not put working documents in the vault. Links inside the files in `planning/` were written when they sat in the vault and may no longer resolve.

## Site / framework

- Pipeline: Parse → Filter → Transform → Emit (`quartz/build.ts`). Plugin selection and theme live in `quartz.config.ts`; page layout (sidebars, explorer, graph, backlinks) in `quartz.layout.ts`.
- Local divergences from upstream Quartz are all about folder notes and folder links: `quartz/util/path.ts` (`getFolderNotes`, `fileSlug`, `transformLink`), `quartz/processors/parse.ts`, `quartz/build.ts`, `quartz/plugins/emitters/folderPage.tsx`, and `quartz/components/scripts/spa.inline.ts`. They are covered by `quartz/util/path.test.ts`; re-check them after pulling upstream Quartz changes.
- `quartz/bootstrap-cli.mjs` is plain ESM JavaScript — no TypeScript syntax there. TypeScript is strict with `noUnusedLocals` and `noUnusedParameters`; JSX is Preact.
- `Plugin.CustomOgImages()` dominates build time; comment it out in `quartz.config.ts` for faster local iteration, and don't commit that change.
- `baseUrl` in `quartz.config.ts` feeds the sitemap, RSS and OG image URLs, so it must match the deployed domain.

## Do not edit

- `content/.obsidian/` — Obsidian's own workspace state. `workspace.json` is usually dirty in `git status`; don't commit or revert it as part of other work.
- `quartz/util/emojimap.json`, `quartz/.quartz-cache/`, `public/`, `tsconfig.tsbuildinfo` — generated.
