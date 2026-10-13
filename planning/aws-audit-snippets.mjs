// Parse snippets without executing them or calling AWS. Fragments can fail by design.
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { unified } from "unified";
import remarkParse from "remark-parse";
import { visit } from "unist-util-visit";

const walk = (dir) =>
  fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(dir, entry.name);
    return entry.isDirectory()
      ? walk(file)
      : file.endsWith(".md")
        ? [file]
        : [];
  });
let checked = 0;
let failed = 0;
for (const file of walk("content/AWS")) {
  const raw = fs.readFileSync(file, "utf8");
  const snippets = [];
  visit(unified().use(remarkParse).parse(raw), "code", (node) => {
    if (["json", "python", "bash", "sh"].includes(node.lang))
      snippets.push(node);
  });
  for (const snippet of snippets) {
    checked++;
    const line = snippet.position.start.line;
    let error = "";
    if (snippet.lang === "json") {
      try {
        JSON.parse(snippet.value);
      } catch (err) {
        error = err.message;
      }
    } else {
      const python = snippet.lang === "python";
      const result = spawnSync(
        python ? "python3" : "bash",
        python
          ? ["-c", "import ast, sys; ast.parse(sys.stdin.read())"]
          : ["-n"],
        { input: snippet.value, encoding: "utf8" },
      );
      if (result.status !== 0 || result.error)
        error = result.error?.message ?? result.stderr.trim();
    }
    if (error) {
      failed++;
      console.log(
        `${file}:${line} (${snippet.lang}): ${error.replace(/\n/g, " | ")}`,
      );
    }
  }
}
console.log(
  `Checked ${checked} fenced JSON/Python/shell blocks; ${failed} parse failures. Fragments require human classification. No snippets executed.`,
);
if (failed) process.exitCode = 1;
