import fs from "node:fs";
import path from "node:path";

const CONTENT_DIR = path.resolve("content");
const K8S_DIR = path.resolve("content/Kubernetes");

// Gather all existing files and slugs in content/
const allFiles = [];
function scanDir(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== ".obsidian") {
        scanDir(fullPath);
      }
    } else if (entry.name.endsWith(".md")) {
      allFiles.push(fullPath);
    }
  }
}
scanDir(CONTENT_DIR);

// Build map of available targets
// In Quartz: file path relative to content without .md, lowercase/sluggified, filename only, etc.
const slugSet = new Set();
const fileBasenameSet = new Map(); // basename -> array of relative paths
const exactRelativeSet = new Set();

for (const file of allFiles) {
  const rel = path.relative(CONTENT_DIR, file).replace(/\.md$/, "");
  exactRelativeSet.add(rel);
  slugSet.add(rel.toLowerCase());
  
  const base = path.basename(file, ".md");
  if (!fileBasenameSet.has(base)) {
    fileBasenameSet.set(base, []);
  }
  fileBasenameSet.get(base).push(rel);

  // Parse aliases from frontmatter if present
  try {
    const raw = fs.readFileSync(file, "utf8");
    if (raw.startsWith("---")) {
      const end = raw.indexOf("\n---", 3);
      if (end !== -1) {
        const fm = raw.slice(3, end);
        const aliasMatch = fm.match(/aliases\s*:\s*\[(.*?)\]/) || fm.match(/aliases\s*:\s*\n((?:\s*-\s*[^\n]+\n?)+)/);
        if (aliasMatch) {
          if (aliasMatch[1].includes("-")) {
            const list = aliasMatch[1].split("\n").map(s => s.replace(/^\s*-\s*/, "").trim()).filter(Boolean);
            for (const a of list) {
              exactRelativeSet.add(a);
              slugSet.add(a.toLowerCase());
            }
          } else {
            const list = aliasMatch[1].split(",").map(s => s.trim().replace(/^['"]|['"]$/g, "")).filter(Boolean);
            for (const a of list) {
              exactRelativeSet.add(a);
              slugSet.add(a.toLowerCase());
            }
          }
        }
      }
    }
  } catch {}
}

// Function to resolve a wikilink target
function resolveWikilink(link, sourceRelPath) {
  // link could be "Kubernetes/concepts/00-hub" or "00-start-here" or "Kubernetes/concepts/L01-architecture"
  let cleanLink = link.trim();
  // Strip anchors #...
  if (cleanLink.includes("#")) {
    cleanLink = cleanLink.split("#")[0].trim();
  }
  if (!cleanLink) {
    return true; // Anchor-only link within page
  }

  // If link has an extension like .png, .jpg, check if file exists
  if (/\.(png|jpg|jpeg|svg|gif|pdf)$/i.test(cleanLink)) {
    const assetPath = path.resolve(CONTENT_DIR, cleanLink);
    return fs.existsSync(assetPath);
  }

  // 1. Exact relative match from content root
  if (exactRelativeSet.has(cleanLink) || slugSet.has(cleanLink.toLowerCase())) {
    return true;
  }

  // 2. Relative to current file's directory
  const currentDir = path.dirname(sourceRelPath);
  const relativeFromCurrent = path.normalize(path.join(currentDir, cleanLink));
  if (exactRelativeSet.has(relativeFromCurrent) || slugSet.has(relativeFromCurrent.toLowerCase())) {
    return true;
  }

  // 3. Shortest / basename match
  const base = path.basename(cleanLink);
  if (fileBasenameSet.has(base)) {
    return true;
  }

  // 4. Directory match (if a directory exists, Quartz might generate folder page, but link should ideally be exact)
  const dirPath = path.resolve(CONTENT_DIR, cleanLink);
  if (fs.existsSync(dirPath) && fs.statSync(dirPath).isDirectory()) {
    return "directory";
  }

  return false;
}

// Scan all Kubernetes files for issues
const issues = [];
const k8sFiles = allFiles.filter(f => f.startsWith(K8S_DIR));

for (const file of k8sFiles) {
  const relPath = path.relative(CONTENT_DIR, file);
  const content = fs.readFileSync(file, "utf8");
  const stats = fs.statSync(file);

  // 1. Empty file
  if (stats.size === 0 || content.trim().length === 0) {
    issues.push({ file: relPath, type: "EMPTY_FILE", message: "File is completely empty (0 bytes)" });
    continue;
  }

  // 2. Frontmatter check
  const hasFrontmatter = content.startsWith("---");
  let frontmatterObj = {};
  if (!hasFrontmatter) {
    issues.push({ file: relPath, type: "MISSING_FRONTMATTER", message: "Missing frontmatter '---' at start of file" });
  } else {
    const secondDelim = content.indexOf("\n---", 3);
    if (secondDelim === -1) {
      issues.push({ file: relPath, type: "MALFORMED_FRONTMATTER", message: "Frontmatter closing '---' not found" });
    } else {
      const fmLines = content.slice(3, secondDelim).split("\n");
      for (const line of fmLines) {
        const match = line.match(/^([a-zA-Z0-9_-]+)\s*:\s*(.*)$/);
        if (match) {
          frontmatterObj[match[1]] = match[2];
        }
      }
      if (!frontmatterObj.title) {
        issues.push({ file: relPath, type: "MISSING_TITLE", message: "Frontmatter missing 'title'" });
      }
    }
  }

  // Strip fenced code blocks and inline code before parsing wikilinks
  const contentWithoutCode = content
    .replace(/```[\s\S]*?```/g, "")
    .replace(/`[^`\n]+`/g, "");

  // 3. H1 check (ignore if draft)
  const lines = content.split("\n");
  const hasH1 = lines.some(l => /^#\s+[^#]/.test(l));
  if (!hasH1 && !frontmatterObj.draft) {
    issues.push({ file: relPath, type: "MISSING_H1", message: "Page has no top-level H1 (# Heading)" });
  }

  // 4. Table check: lines starting with ||
  lines.forEach((l, idx) => {
    if (l.trim().startsWith("||")) {
      issues.push({ file: relPath, line: idx + 1, type: "MALFORMED_TABLE", message: `Malformed table row starting with '||': ${l.trim().slice(0, 40)}` });
    }
  });

  // 5. Wikilinks check
  const wikilinkRegex = /\[\[([^\]]+)\]\]/g;
  let match;
  while ((match = wikilinkRegex.exec(contentWithoutCode)) !== null) {
    const rawInner = match[1];
    // Split target and alias by | or \|
    const parts = rawInner.split(/\\?\|/);
    let rawTarget = parts[0].trim();
    if (!rawTarget) continue;

    const resolved = resolveWikilink(rawTarget, relPath);
    if (resolved === false) {
      issues.push({ file: relPath, type: "BROKEN_LINK", message: `Broken wikilink target: [[${rawTarget}]]` });
    } else if (resolved === "directory") {
      issues.push({ file: relPath, type: "DIRECTORY_LINK", message: `Wikilink points to directory instead of markdown page: [[${rawTarget}]]` });
    }
  }
}

const criticalTypes = new Set(["EMPTY_FILE", "MALFORMED_FRONTMATTER", "BROKEN_LINK", "DIRECTORY_LINK", "MALFORMED_TABLE", "MISSING_H1"]);
const isStrict = process.argv.includes("--strict");
const criticalIssues = issues.filter(i => isStrict || criticalTypes.has(i.type));
const warningIssues = issues.filter(i => !isStrict && !criticalTypes.has(i.type));

// Report
console.log(`\n=== Kubernetes Content Validation Report ===`);
console.log(`Total files scanned: ${k8sFiles.length}`);
console.log(`Critical errors: ${criticalIssues.length}`);
console.log(`Warnings / pending migrations: ${warningIssues.length}\n`);

const issuesByType = {};
for (const issue of issues) {
  issuesByType[issue.type] = (issuesByType[issue.type] || 0) + 1;
}

for (const [type, count] of Object.entries(issuesByType)) {
  const isCrit = criticalTypes.has(type);
  console.log(`- ${type}: ${count} ${isCrit ? "❌ (critical)" : "⚠️ (warning/pending)"}`);
}

if (criticalIssues.length > 0) {
  console.log("\nDetailed Critical Errors:");
  for (const issue of criticalIssues) {
    const loc = issue.line ? `${issue.file}:${issue.line}` : issue.file;
    console.log(`[${issue.type}] ${loc} - ${issue.message}`);
  }
}

if (warningIssues.length > 0 && process.argv.includes("--verbose")) {
  console.log("\nDetailed Warnings:");
  for (const issue of warningIssues) {
    const loc = issue.line ? `${issue.file}:${issue.line}` : issue.file;
    console.log(`[${issue.type}] ${loc} - ${issue.message}`);
  }
}

if (criticalIssues.length > 0) {
  console.error(`\nFailed with ${criticalIssues.length} critical issues.`);
  process.exit(1);
} else {
  console.log("\nAll critical Kubernetes structural validations passed! ✅");
  process.exit(0);
}

