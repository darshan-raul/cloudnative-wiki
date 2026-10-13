import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, test } from "node:test";
import matter from "gray-matter";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import { visit } from "unist-util-visit";

const repo = fileURLToPath(new URL("../", import.meta.url));
function markdownFiles(directory: string): string[] {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory()
      ? markdownFiles(file)
      : entry.name.endsWith(".md")
        ? [file]
        : [];
  });
}
const notes = [
  path.join(repo, "content/AWS.md"),
  ...markdownFiles(path.join(repo, "content/AWS")),
].map((file) => {
  const { content, data } = matter(fs.readFileSync(file, "utf8"));
  return {
    file: path.relative(repo, file),
    content,
    data,
    tree: unified()
      .use(remarkParse)
      .use(remarkGfm)
      .use(remarkMath)
      .parse(content),
  };
});

describe("AWS learning-note regressions", () => {
  test("notes retain hierarchical tags and owning documentation references", () => {
    for (const note of notes) {
      assert(
        Array.isArray(note.data.tags),
        `${note.file}: tags must be a list`,
      );
      assert(note.data.tags.length > 0, `${note.file}: missing tags`);
      for (const tag of note.data.tags) {
        assert(
          typeof tag === "string" && tag.includes("/"),
          `${note.file}: non-hierarchical tag ${String(tag)}`,
        );
      }
      const prose = note.content.replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm, "");
      assert.match(
        prose,
        /https:\/\/docs\.aws\.amazon\.com\//,
        `${note.file}: add an owning AWS documentation reference`,
      );
    }
  });

  test("table rows have the same width as their header", () => {
    for (const note of notes) {
      visit(note.tree, "table", (table) => {
        const width = table.children[0].children.length;
        for (const row of table.children) {
          assert.equal(
            row.children.length,
            width,
            `${note.file}:${row.position?.start.line}: inconsistent table width`,
          );
        }
      });
    }
  });

  test("currency examples are not parsed as unintended math", () => {
    for (const note of notes) {
      visit(note.tree, (node) => {
        if (node.type !== "inlineMath" && node.type !== "math") return;
        assert(
          !/^(?:\d|\.\d)/.test(node.value) ||
            !/(?:cost|\/hour|\/month|per million|requests)/i.test(node.value),
          `${note.file}:${node.position?.start.line}: escape currency dollar signs`,
        );
      });
    }
  });

  test("JSON examples contain complete, parseable documents", () => {
    for (const note of notes) {
      visit(note.tree, "code", (code) => {
        if (code.lang !== "json") return;
        assert.doesNotThrow(
          () => JSON.parse(code.value),
          `${note.file}:${code.position?.start.line}: label fragments explicitly`,
        );
      });
    }
  });
});
