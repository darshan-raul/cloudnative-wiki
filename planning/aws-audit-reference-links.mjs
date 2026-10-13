// Check external AWS reference availability; HTTP errors do not prove link rot.
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
const references = new Map();
for (const file of ["content/AWS.md", ...walk("content/AWS")]) {
  const body = fs
    .readFileSync(file, "utf8")
    .replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm, "");
  for (const match of body.matchAll(/https?:\/\/[^\s)>\]`"']+/g)) {
    const url = match[0].replace(/[.,;]+$/, "");
    if (!/^https?:\/\/(?:docs\.aws\.amazon\.com|aws\.amazon\.com)\//.test(url))
      continue;
    if (!references.has(url)) references.set(url, []);
    references.get(url).push(file);
  }
}
const entries = [...references];
const results = [];
let cursor = 0;
async function worker() {
  while (cursor < entries.length) {
    const [url, files] = entries[cursor++];
    try {
      let response = await fetch(url, {
        method: "HEAD",
        signal: AbortSignal.timeout(10000),
      });
      if ([403, 404, 405].includes(response.status))
        response = await fetch(url, { signal: AbortSignal.timeout(10000) });
      results.push({
        url,
        status: response.status,
        finalUrl: response.url,
        files: [...new Set(files)],
      });
      await response.body?.cancel();
    } catch (error) {
      results.push({
        url,
        status: "unverified",
        error: error.message,
        files: [...new Set(files)],
      });
    }
  }
}
await Promise.all(Array.from({ length: 8 }, worker));
console.log(
  JSON.stringify(
    results.sort((a, b) => a.url.localeCompare(b.url)),
    null,
    2,
  ),
);
