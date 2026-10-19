---
title: "Stack vs Heap Memory & Stack Overflow"
description: "Stack and heap memory explained with simple mental models, how variables are allocated, and what causes a stack overflow."
tags:
  - architecture
  - programming-concepts
  - memory-management
  - stack-heap-and-stack-overflow
date: 2026-10-19
---

# Stack vs Heap Memory & Stack Overflow 📚

When your program runs, the operating system assigns it a chunk of memory (RAM). The runtime divides this memory into two main areas for storing variables and data: **The Stack** and **The Heap**.

Understanding the difference helps you write bug-free code, understand variable lifecycles, and debug program crashes.

---

## 1. The Mental Model

```
       THE STACK                                 THE HEAP
┌─────────────────────────┐               ┌─────────────────────────┐
│ Function Call C (top)   │               │  [User object]          │
├─────────────────────────┤               │     name: "Alice"       │
│ Function Call B         │               │     cart: [101, 102]    │
├─────────────────────────┤               │                         │
│ Function Call A (main)  │               │  [Huge Image Buffer]    │
└─────────────────────────┘               │  [Dynamic Array / List] │
  Strict, fast, automatic                  └─────────────────────────┘
  (LIFO: Last-In, First-Out)                Flexible, shared, dynamic
```

### The Stack (A Stack of Trays)

Think of the stack like a stack of cafeteria trays:

- You put a tray on top (**Push**).
- You take the top tray off (**Pop**).
- You cannot pull a tray from the bottom without knocking everything over.
- **What goes here:** Function calls, function arguments, and simple local variables (like `int`, `bool`, or local pointers).
- **Lifetime:** Temporary. When a function finishes running, its tray is automatically discarded.

### The Heap (A Hotel Storage Room)

Think of the heap like a large hotel storage room with numbered shelves:

- You ask the front desk for storage space (**Allocation**).
- They give you a key/ticket (a **pointer or reference**) pointing to your shelf.
- Anyone with the key can access or update that item from anywhere in the program.
- **What goes here:** Large objects, dynamically sized data (arrays that grow, strings, maps), and data that needs to stay alive after a function returns.
- **Lifetime:** Long-lived. Remains until you explicitly free it or the [[Architecture/programming-concepts/garbage-collection-basics|Garbage Collector]] cleans it up.

---

## 2. Key Differences at a Glance

| Feature          | The Stack                                   | The Heap                                          |
| :--------------- | :------------------------------------------ | :------------------------------------------------ |
| **Organization** | Linear, strict (Last-In, First-Out)         | Free-form pool of memory blocks                   |
| **Speed**        | ⚡ Super fast (just moving a pointer)       | 🐢 Slower (finding free space, managing memory)   |
| **Size Limit**   | Small & fixed (typically 1–8 MB per thread) | Large (bounded only by system RAM)                |
| **Allocation**   | Automatic when a function is called         | Manual (`malloc`/`new`) or managed by runtime     |
| **Deallocation** | Automatic when function returns             | Explicit `free()` or automatic Garbage Collection |
| **Safety**       | Isolated to the current function/thread     | Shared across threads (risks race conditions)     |

---

## 3. How Stack & Heap Work in Code

Let's look at what happens in memory when this simple code runs:

```python
def calculate_total(price, tax_rate):
    # 'price' and 'tax_rate' live on the STACK
    tax = price * tax_rate       # 'tax' lives on the STACK
    total = price + tax          # 'total' lives on the STACK
    return total

def main():
    item_price = 100             # STACK variable
    # A list with dynamic size lives on the HEAP.
    # 'receipt' is a reference on the stack pointing to the heap object!
    receipt = ["Widget", item_price]

    final_amount = calculate_total(item_price, 0.08)
    print(final_amount)

main()
```

### Step-by-Step Memory Walkthrough

1. `main()` is called: A **stack frame** for `main` is placed on the stack holding `item_price` and the `receipt` reference.
2. The list `["Widget", 100]` is created on the **heap** because its size can grow dynamically.
3. `calculate_total()` is called: A new stack frame is pushed on top of `main` holding `price`, `tax_rate`, and `tax`.
4. `calculate_total()` finishes: Its stack frame is **instantly popped off and deleted**. Memory is freed immediately.
5. Control returns to `main()`.

---

## 4. What is a Stack Overflow?

Because the stack has a small, fixed size (often 1 MB to 8 MB), pushing too many frames onto it runs out of stack space. When the stack crashes into protected memory, the operating system kills the process. This crash is called a **Stack Overflow**.

```
┌─────────────────────────────────┐
│ calculate(100000) frame         │
├─────────────────────────────────┤
│ ...                             │
├─────────────────────────────────┤
│ calculate(2) frame              │
├─────────────────────────────────┤
│ calculate(1) frame              │
├─────────────────────────────────┤
│ main() frame                    │
└─────────────────────────────────┘
💥 BOOM: Stack Limit Exceeded! (Stack Overflow)
```

### The #1 Cause: Infinite Recursion

The most common reason for a stack overflow is a recursive function without a proper **base case** (condition to stop):

```python
# ❌ BUG: Infinite recursion causes Stack Overflow
def countdown(n):
    print(n)
    return countdown(n - 1)  # Keeps calling itself forever!

countdown(5)
# Python output: RecursionError: maximum recursion depth exceeded
```

```python
# ✅ FIXED: Adding a base case stops recursion cleanly
def countdown(n):
    if n <= 0:  # Base case: STOP!
        print("Blast off! 🚀")
        return
    print(n)
    return countdown(n - 1)

countdown(5)
```

### Other Causes

- **Excessively large local variables:** Declaring a huge array (e.g., 10 MB array) as a local variable inside a function rather than allocating it on the heap.
- **Deeply nested data:** Parsing an XML, JSON, or YAML document with 10,000 nested brackets using a recursive parser.

---

## Across the Wiki

- [[Architecture/programming-concepts/value-vs-reference-and-pointers|Value vs Reference & Pointers]] — How stack variables point to heap objects.
- [[Architecture/programming-concepts/recursion-vs-iteration|Recursion vs Iteration]] — How to convert recursive code into loops to prevent stack overflow.
- [[Architecture/programming-concepts/garbage-collection-basics|Garbage Collection Basics]] — How memory on the heap is reclaimed.
- [[Architecture/solution-architecture-concepts/reliability/memory-leaks|Memory Leaks]] — When heap memory grows uncontrollably.
