---
title: "Recursion vs Iteration: When to Use Loops vs Recursive Calls"
description: "How recursion works under the hood with stack frames, base cases, when to use recursion for trees/graphs, and recursion vs iteration trade-offs."
tags:
  - architecture
  - programming-concepts
  - algorithms
  - recursion
date: 2026-10-19
---

# Recursion vs Iteration: When to Use Loops vs Recursive Calls 🔄

Every repetitive computation in software can be solved using either **Iteration** (loops: `for`, `while`) or **Recursion** (a function calling itself with a smaller input).

Knowing when to choose each approach helps you write cleaner code while avoiding [[Architecture/programming-concepts/stack-heap-and-stack-overflow|Stack Overflows]].

---

## 1. The Real-World Analogy: Russian Matryoshka Dolls

Imagine you are looking for a small coin hidden inside a nested set of wooden Russian dolls:

- **Iterative Approach (Loop):** You line up the dolls on a table. In a `while` loop, you open one doll, check for the coin, move to the next doll, and repeat until found.
- **Recursive Approach:** You open a doll. If it has a smaller doll inside, you ask yourself: _"How do I find a coin in this smaller doll?"_ You apply the exact same function to the smaller doll until you reach the smallest solid doll (**Base Case**).

```
RECURSION:
  open_doll(doll_5)
    open_doll(doll_4)
      open_doll(doll_3)
        open_doll(doll_2)
          open_doll(doll_1) ──▶ Found coin! (Base Case)
        return
      return
    return
  return
```

---

## 2. The Two Essential Rules of Recursion

Every working recursive function must have two parts:

1. **The Base Case:** The exit condition where the function stops calling itself and returns directly.
2. **The Recursive Step:** Calling itself with an input that is **strictly closer** to the base case.

```python
def factorial(n):
    # 1. Base Case: stops the recursion
    if n <= 1:
        return 1

    # 2. Recursive Step: n * factorial(n - 1) moves closer to 1
    return n * factorial(n - 1)
```

Without a base case, the function calls itself indefinitely until the call stack fills up, triggering a **Stack Overflow**.

---

## 3. When is Recursion Actually Better?

For flat, linear lists (like searching an array of numbers), a standard `for` loop is almost always faster and safer.

Recursion truly shines when dealing with **nested, branching, hierarchical data structures**:

- **File Systems / Directory Trees:** Folders containing folders containing files.
- **JSON / YAML Documents:** Deeply nested configuration or API payloads.
- **DOM / UI Trees:** HTML elements containing child divs and spans.
- **Graph & Tree Algorithms:** Traversing organizational charts or dependency trees.

### Example: Listing All Files in a Nested Directory

```python
import os

# Clean, elegant recursive directory walker
def find_markdown_files(directory):
    md_files = []
    for entry in os.scandir(directory):
        if entry.is_file() and entry.name.endswith(".md"):
            md_files.append(entry.path)
        elif entry.is_dir():
            # Recurse on the subdirectory!
            md_files.extend(find_markdown_files(entry.path))
    return md_files
```

Writing this with an iterative `while` loop requires manually maintaining a stack data structure in memory.

---

## 4. Trade-Off Comparison

| Dimension            | Iteration (Loops)                      | Recursion                                          |
| :------------------- | :------------------------------------- | :------------------------------------------------- |
| **How it stops**     | Loop condition becomes false           | Base case is met                                   |
| **Memory usage**     | $\mathcal{O}(1)$ constant memory       | $\mathcal{O}(N)$ stack memory (one frame per call) |
| **Risk of crash**    | Infinite loop freezes CPU / burns 100% | Infinite recursion crashes with **Stack Overflow** |
| **Execution speed**  | Fast (simple CPU counter increment)    | Slightly slower (function call overhead)           |
| **Code readability** | Best for flat arrays and simple counts | Best for trees, graphs, and divide-and-conquer     |

---

## Across the Wiki

- [[Architecture/programming-concepts/stack-heap-and-stack-overflow|Stack vs Heap & Stack Overflow]] — Visualizing how recursive calls push stack frames.
- [[Architecture/programming-concepts/compiled-vs-interpreted|Compiled vs Interpreted Languages]] — How compilers optimize function calls.
