// Structural validator for every note in content/.
//
//   node scripts/check-content.mjs                 validate the whole vault
//   node scripts/check-content.mjs Kubernetes AWS  only report issues under these top-level paths
//   node scripts/check-content.mjs --verbose       list warnings as well as errors
//   node scripts/check-content.mjs --strict        treat warnings as errors
//
// Link targets are always resolved against the whole vault, even when the
// report is limited to some paths.

import fs from "node:fs";
import path from "node:path";

const CONTENT_DIR = path.resolve("content");
const REQUIRED_FRONTMATTER = ["title", "tags", "date", "description"];
const ASSET_EXTENSION =
  /\.(png|jpe?g|svg|gif|webp|pdf|ya?ml|json|sh|txt|csv)$/i;
// Notes with fewer prose words than this are reported as stubs (warning).
const STUB_WORDS = 40;
// The home page is the root of the graph and needs no inbound link.
const ORPHAN_EXEMPT = new Set(["index"]);

const args = process.argv.slice(2);
const isStrict = args.includes("--strict");
const isVerbose = args.includes("--verbose");
const scopes = args.filter((a) => !a.startsWith("--"));

const criticalTypes = new Set([
  "EMPTY_FILE",
  "MISSING_FRONTMATTER",
  "MALFORMED_FRONTMATTER",
  "MISSING_FIELD",
  "MISSING_H1",
  "MALFORMED_TABLE",
  "UNESCAPED_TABLE_LINK",
  "UNCLOSED_CODE_FENCE",
  "BROKEN_LINK",
  "AMBIGUOUS_LINK",
  "DIRECTORY_LINK",
  "ORPHAN",
]);

// ---------------------------------------------------------------------------
// Collect notes
// ---------------------------------------------------------------------------

const notes = [];
function scanDir(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      scanDir(fullPath);
    } else if (entry.name.endsWith(".md")) {
      const rel = path.relative(CONTENT_DIR, fullPath);
      notes.push({
        file: fullPath,
        rel,
        slug: rel.replace(/\.md$/, ""),
        raw: fs.readFileSync(fullPath, "utf8"),
      });
    }
  }
}
scanDir(CONTENT_DIR);

// ---------------------------------------------------------------------------
// Frontmatter
// ---------------------------------------------------------------------------

function parseFrontmatter(raw) {
  if (!raw.startsWith("---"))
    return { state: "missing", fields: {}, body: raw };
  const end = raw.indexOf("\n---", 3);
  if (end === -1) return { state: "malformed", fields: {}, body: raw };
  const block = raw.slice(3, end);
  const fields = {};
  for (const line of block.split("\n")) {
    const match = line.match(/^([a-zA-Z0-9_-]+)\s*:\s*(.*)$/);
    if (match) fields[match[1]] = match[2].trim();
  }
  // aliases may be written inline or as a YAML list
  const aliases = [];
  const inline = block.match(/^aliases\s*:\s*\[(.*?)\]/m);
  const list = block.match(/^aliases\s*:\s*\n((?:\s*-\s*[^\n]+\n?)+)/m);
  if (inline) {
    aliases.push(...inline[1].split(","));
  } else if (list) {
    aliases.push(...list[1].split("\n").map((s) => s.replace(/^\s*-\s*/, "")));
  }
  const bodyStart = raw.indexOf("\n", end + 1);
  return {
    state: "ok",
    fields,
    aliases: aliases
      .map((s) => s.trim().replace(/^['"]|['"]$/g, ""))
      .filter(Boolean),
    body: bodyStart === -1 ? "" : raw.slice(bodyStart + 1),
  };
}

for (const note of notes) {
  Object.assign(note, parseFrontmatter(note.raw));
}

// ---------------------------------------------------------------------------
// Link resolution — mirrors Quartz's "shortest" strategy, but strictly:
// a bare basename must be unique to count.
// ---------------------------------------------------------------------------

const bySlug = new Map();
const byBasename = new Map();
for (const note of notes) {
  bySlug.set(note.slug.toLowerCase(), note);
  const base = path.basename(note.slug).toLowerCase();
  if (!byBasename.has(base)) byBasename.set(base, []);
  byBasename.get(base).push(note);
}
for (const note of notes) {
  for (const alias of note.aliases ?? []) {
    const key = alias.toLowerCase();
    if (!bySlug.has(key)) bySlug.set(key, note);
  }
}

function resolveWikilink(target, fromSlug) {
  const clean = target.replace(/\.md$/, "").replace(/\/$/, "");
  const key = clean.toLowerCase();

  if (bySlug.has(key)) return { note: bySlug.get(key) };

  const relative = path
    .normalize(path.join(path.dirname(fromSlug), clean))
    .toLowerCase();
  if (bySlug.has(relative)) return { note: bySlug.get(relative) };

  if (!clean.includes("/")) {
    const candidates = byBasename.get(key);
    if (candidates?.length === 1) return { note: candidates[0] };
    if (candidates?.length > 1) return { ambiguous: candidates };
  }

  const dirPath = path.resolve(CONTENT_DIR, clean);
  if (fs.existsSync(dirPath) && fs.statSync(dirPath).isDirectory()) {
    return { directory: true };
  }
  return {};
}

// ---------------------------------------------------------------------------
// Per-note checks
// ---------------------------------------------------------------------------

const issues = [];
const inbound = new Map(notes.map((n) => [n.slug, 0]));

function report(note, type, message, line) {
  issues.push({ file: note.rel, type, message, line });
}

for (const note of notes) {
  const { raw, body, fields } = note;

  if (raw.trim().length === 0) {
    report(note, "EMPTY_FILE", "File is empty");
    continue;
  }

  if (note.state === "missing") {
    report(
      note,
      "MISSING_FRONTMATTER",
      "No frontmatter block at start of file",
    );
  } else if (note.state === "malformed") {
    report(
      note,
      "MALFORMED_FRONTMATTER",
      "Frontmatter closing '---' not found",
    );
  } else {
    for (const field of REQUIRED_FRONTMATTER) {
      if (!(field in fields)) {
        report(note, "MISSING_FIELD", `Frontmatter missing '${field}'`);
      }
    }
  }

  const isDraft = fields.draft === "true";
  const lines = raw.split("\n");

  // Code fences: track state per line so tables and links inside them are skipped
  let inFence = false;
  let fenceCount = 0;
  const proseLines = [];
  lines.forEach((line, idx) => {
    if (/^\s*(```|~~~)/.test(line)) {
      inFence = !inFence;
      fenceCount++;
      return;
    }
    if (inFence) return;
    proseLines.push({ text: line, number: idx + 1 });
  });
  if (fenceCount % 2 !== 0) {
    report(note, "UNCLOSED_CODE_FENCE", "Odd number of code fence markers");
  }

  const bodyOffset = raw.length - body.length;
  const bodyStartLine = raw.slice(0, bodyOffset).split("\n").length;
  const bodyProse = proseLines.filter((l) => l.number >= bodyStartLine);

  if (!isDraft && !bodyProse.some((l) => /^#\s+\S/.test(l.text))) {
    report(note, "MISSING_H1", "Page has no top-level H1 (# Heading)");
  }

  let words = 0;
  for (const { text, number } of bodyProse) {
    const trimmed = text.trim();
    const isTableRow = trimmed.startsWith("|");

    if (trimmed.startsWith("||")) {
      report(
        note,
        "MALFORMED_TABLE",
        `Table row starts with '||': ${trimmed.slice(0, 40)}`,
        number,
      );
    }

    const withoutInlineCode = text.replace(/`[^`\n]+`/g, "");
    words += (
      withoutInlineCode.replace(/https?:\/\/\S+/g, "").match(/[A-Za-z]{2,}/g) ??
      []
    ).length;

    for (const match of withoutInlineCode.matchAll(/!?\[\[([^\]\n]+?)\]\]/g)) {
      const inner = match[1];
      const pipe = inner.match(/^(.*?)(\\?)\|(.*)$/s);
      if (isTableRow && pipe && pipe[2] !== "\\") {
        report(
          note,
          "UNESCAPED_TABLE_LINK",
          `Wikilink alias in a table must use '\\|': [[${inner}]]`,
          number,
        );
      }
      const target = (pipe ? pipe[1] : inner).split("#")[0].trim();
      if (!target) continue; // anchor within the same page

      if (ASSET_EXTENSION.test(target)) {
        const fromRoot = path.resolve(CONTENT_DIR, target);
        const fromNote = path.resolve(path.dirname(note.file), target);
        if (!fs.existsSync(fromRoot) && !fs.existsSync(fromNote)) {
          report(note, "BROKEN_LINK", `Missing asset: [[${target}]]`, number);
        }
        continue;
      }

      const resolved = resolveWikilink(target, note.slug);
      if (resolved.note) {
        if (resolved.note !== note) {
          inbound.set(resolved.note.slug, inbound.get(resolved.note.slug) + 1);
        }
      } else if (resolved.ambiguous) {
        report(
          note,
          "AMBIGUOUS_LINK",
          `[[${target}]] matches ${resolved.ambiguous.length} notes — use a full path`,
          number,
        );
      } else if (resolved.directory) {
        report(
          note,
          "DIRECTORY_LINK",
          `Wikilink points to a directory, not a page: [[${target}]]`,
          number,
        );
      } else {
        report(note, "BROKEN_LINK", `Broken wikilink: [[${target}]]`, number);
      }
    }
  }

  if (!isDraft && words < STUB_WORDS) {
    report(note, "STUB", `Only ${words} words of prose`);
  }
  note.isDraft = isDraft;
}

for (const note of notes) {
  if (note.isDraft || ORPHAN_EXEMPT.has(note.slug)) continue;
  if (inbound.get(note.slug) === 0) {
    report(note, "ORPHAN", "No other note links to this page");
  }
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

const inScope = (issue) =>
  scopes.length === 0 ||
  scopes.some(
    (s) => issue.file === `${s}.md` || issue.file.startsWith(`${s}/`),
  );
const scoped = issues.filter(inScope);
const isCritical = (issue) => isStrict || criticalTypes.has(issue.type);
const criticalIssues = scoped.filter(isCritical);
const warningIssues = scoped.filter((i) => !isCritical(i));

console.log(`\n=== Content Validation Report ===`);
console.log(
  `Notes scanned: ${notes.length}${scopes.length ? ` (reporting on: ${scopes.join(", ")})` : ""}`,
);
console.log(`Errors: ${criticalIssues.length}`);
console.log(`Warnings: ${warningIssues.length}\n`);

const countByType = {};
for (const issue of scoped) {
  countByType[issue.type] = (countByType[issue.type] ?? 0) + 1;
}
for (const [type, count] of Object.entries(countByType)) {
  const critical = isStrict || criticalTypes.has(type);
  console.log(
    `- ${type}: ${count} ${critical ? "❌ (error)" : "⚠️ (warning)"}`,
  );
}

function printIssues(list) {
  for (const issue of list) {
    const location = issue.line ? `${issue.file}:${issue.line}` : issue.file;
    console.log(`[${issue.type}] ${location} - ${issue.message}`);
  }
}

if (criticalIssues.length > 0) {
  console.log("\nErrors:");
  printIssues(criticalIssues);
}
if (warningIssues.length > 0 && isVerbose) {
  console.log("\nWarnings:");
  printIssues(warningIssues);
}

if (criticalIssues.length > 0) {
  console.error(`\nFailed with ${criticalIssues.length} errors.`);
  process.exit(1);
}
console.log("\nAll structural content checks passed ✅");
