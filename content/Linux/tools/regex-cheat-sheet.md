---
title: Regular Expressions (Regex) Cheat Sheet
description: Comprehensive regular expressions reference for software and DevOps engineers — character classes, quantifiers, lookarounds, and battle-tested DevOps regex recipes
tags:
  - regex
  - cheat-sheet
  - devops
  - tooling
date: 2026-10-10
---

# Regular Expressions (Regex) Cheat Sheet

A **Regular Expression (Regex)** is a sequence of characters that specifies a search pattern in text. They are ubiquitous across Linux CLI tools (`grep`, `sed`, `awk`), programming languages, log parsing filters (Vector, FluentBit), and WAF security rules.

---

## 1. Character Classes & Metacharacters

| Pattern  | Matches                                              | Equivalent Set  |
| :------- | :--------------------------------------------------- | :-------------- |
| `.`      | Any character except newline (`\n`)                  | `[^\n]`         |
| `\d`     | Any digit (0-9)                                      | `[0-9]`         |
| `\D`     | Any non-digit                                        | `[^0-9]`        |
| `\w`     | Any word character (alphanumeric + underscore)       | `[a-zA-Z0-9_]`  |
| `\W`     | Any non-word character                               | `[^a-zA-Z0-9_]` |
| `\s`     | Any whitespace (space, tab, newline)                 | `[ \t\r\n\f]`   |
| `\S`     | Any non-whitespace character                         | `[^ \t\r\n\f]`  |
| `[abc]`  | Any character inside the brackets (`a`, `b`, or `c`) | Explicit Set    |
| `[^abc]` | Any character NOT inside the brackets                | Negated Set     |
| `[a-z]`  | Range: any lowercase character from `a` to `z`       | Range           |

---

## 2. Anchors & Boundaries

| Pattern | Meaning                            | Example                                          |
| :------ | :--------------------------------- | :----------------------------------------------- |
| `^`     | Start of line (or start of string) | `^Error` (Matches line starting with "Error")    |
| `$`     | End of line (or end of string)     | `\.log$` (Matches files ending with ".log")      |
| `\b`    | Word boundary                      | `\bcat\b` (Matches "cat", but not "concatenate") |
| `\B`    | Non-word boundary                  | `\Bcat\B` (Matches inside "concatenate")         |

---

## 3. Quantifiers (Greedy vs Lazy)

| Quantifier | Description               | Behavior                                          |
| :--------- | :------------------------ | :------------------------------------------------ |
| `*`        | 0 or more times           | Greedy (matches as many as possible)              |
| `+`        | 1 or more times           | Greedy                                            |
| `?`        | 0 or 1 time (optional)    | Greedy                                            |
| `{n}`      | Exactly $n$ times         | Exact                                             |
| `{n,}`     | At least $n$ times        | Greedy                                            |
| `{n,m}`    | Between $n$ and $m$ times | Greedy                                            |
| `*?`       | 0 or more times           | **Lazy** (matches the fewest characters possible) |
| `+?`       | 1 or more times           | **Lazy**                                          |

---

## 4. Groups, Alternation & Lookarounds

| Syntax         | Type                | Description                                              |
| :------------- | :------------------ | :------------------------------------------------------- |
| `(abc)`        | Capturing Group     | Groups tokens together and creates backreference `$1`    |
| `(?:abc)`      | Non-Capturing Group | Groups tokens without storing backreference (faster)     |
| `(?<name>abc)` | Named Group         | Assigns a key name to captured match                     |
| `a\|b`         | Alternation         | Matches either `a` or `b`                                |
| `(?=...)`      | Positive Lookahead  | Asserts that pattern follows, without including in match |
| `(?!...)`      | Negative Lookahead  | Asserts that pattern does NOT follow                     |
| `(?<=...)`     | Positive Lookbehind | Asserts that pattern precedes match                      |
| `(?<!...)`     | Negative Lookbehind | Asserts that pattern does NOT precede match              |

---

## 5. Battle-Tested DevOps Regex Recipes

### IPv4 Address (Valid Octets 0-255)

```regex
\b(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(?:\.(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])){3}\b
```

### UUIDv4 Format

```regex
\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b
```

### ISO 8601 Timestamp (`YYYY-MM-DDTHH:MM:SSZ`)

```regex
^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$
```

### Semantic Versioning (SemVer)

```regex
^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$
```
