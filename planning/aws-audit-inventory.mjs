// Reproducible inventory; these indicators do not establish technical correctness.
import fs from "node:fs";
import path from "node:path";

const walk = (dir) =>
  fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(dir, entry.name);
    return entry.isDirectory()
      ? walk(file)
      : file.endsWith(".md")
        ? [file]
        : [];
  });
const files = ["content/AWS.md", ...walk("content/AWS")].sort();
const notes = files.map((file) => {
  const raw = fs.readFileSync(file, "utf8");
  const body = raw.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, "");
  const urls = [...body.matchAll(/https?:\/\/[^\s)>]+/g)].map(
    (match) => match[0],
  );
  const prose = body.replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm, "");
  return {
    file,
    words: prose.trim().split(/\s+/).length,
    urls: urls.length,
    primary: urls.filter((url) =>
      /(?:docs\.aws\.amazon\.com|aws\.amazon\.com)\//.test(url),
    ).length,
    docs: urls.filter((url) => url.includes("docs.aws.amazon.com")).length,
    code: (body.match(/^```/gm) ?? []).length / 2,
    headings: body.split("\n").filter((line) => /^#{2,3} /.test(line)),
  };
});
if (process.argv.includes("--json")) {
  console.log(JSON.stringify(notes, null, 2));
} else {
  console.log("# AWS audit inventory\n");
  console.log(
    "Generated from the current worktree with `node planning/aws-audit-inventory.mjs`. Word counts exclude frontmatter and fenced code, but include tables and links. URL counts are occurrences, not link availability checks. Code fences may contain diagrams or incomplete snippets. Every row is structurally inventoried; a row does not imply that every factual claim has been verified.\n",
  );
  console.log(
    `Notes: ${notes.length}. No external URLs: ${notes.filter((n) => !n.urls).length}. No AWS documentation URLs: ${notes.filter((n) => !n.docs).length}. Under 100 words by this counting method: ${notes.filter((n) => n.words < 100).length}.\n`,
  );
  console.log(
    "| Note | Words | URLs | AWS primary URLs | AWS docs URLs | Fenced blocks |\n| --- | ---: | ---: | ---: | ---: | ---: |",
  );
  for (const note of notes) {
    console.log(
      `| [${note.file.replace(/^content\//, "")}](${"../" + note.file}) | ${note.words} | ${note.urls} | ${note.primary} | ${note.docs} | ${note.code} |`,
    );
  }
}
