// Read-only smoke check of emitted AWS articles after a Quartz build.
import fs from "node:fs";
import path from "node:path";
import { fromHtml } from "hast-util-from-html";

const walk = (directory) =>
  fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory()
      ? walk(file)
      : entry.name.endsWith(".md")
        ? [file]
        : [];
  });
const notes = ["content/AWS.md", ...walk("content/AWS")];
const missingPages = [];
const badInternalLinks = [];
const badMarkup = [];
let internalArticleLinks = 0;
for (const source of notes) {
  const standard = source
    .replace(/^content\//, "public/")
    .replace(/\.md$/, ".html");
  // Quartz maps the AWS folder note to AWS/index.html.
  const file = fs.existsSync(standard)
    ? standard
    : standard.replace(/\.html$/, "/index.html");
  if (!fs.existsSync(file)) {
    missingPages.push(file);
    continue;
  }
  const html = fs.readFileSync(file, "utf8");
  const articles = html.match(/<article\b[\s\S]*?<\/article>/g) ?? [];
  if (articles.length === 0) badMarkup.push(`${file}: missing article`);
  function visit(node) {
    if (node.type === "element") {
      const classes = node.properties?.className ?? [];
      if (classes.includes("katex-error"))
        badMarkup.push(`${file}: invalid math rendering`);
      if (node.tagName === "a" && classes.includes("internal")) {
        const href = String(node.properties.href ?? "");
        if (href && !href.startsWith("#") && !/^[a-z]+:/i.test(href)) {
          internalArticleLinks++;
          const raw = decodeURIComponent(href.split("#")[0].split("?")[0]);
          const target = raw.startsWith("/")
            ? path.resolve("public", raw.slice(1))
            : path.resolve(path.dirname(file), raw);
          const candidates = [
            target,
            `${target}.html`,
            path.join(target, "index.html"),
          ];
          if (
            !candidates.some(
              (candidate) =>
                fs.existsSync(candidate) && fs.statSync(candidate).isFile(),
            )
          )
            badInternalLinks.push({ source, href });
        }
      }
    }
    for (const child of node.children ?? []) visit(child);
  }
  for (const article of articles) visit(fromHtml(article, { fragment: true }));
  if (source === "content/AWS/security/cognito.md") {
    const body = articles.join("\n");
    if (!body.includes("Separate tenant-isolation extension"))
      badMarkup.push(`${file}: stale Cognito lesson (rebuild after edits)`);
  }
}
console.log(
  JSON.stringify(
    {
      renderedNotes: notes.length,
      internalArticleLinks,
      missingPages,
      badInternalLinks,
      badMarkup,
    },
    null,
    2,
  ),
);
if (missingPages.length || badInternalLinks.length || badMarkup.length)
  process.exitCode = 1;
