# Programming Concepts Curriculum Improvement Plan

**Date:** 2026-10-19
**Scope:** `content/Architecture/programming-concepts/`
**Target Audience:** Software engineers, cloud-native developers, and architects needing approachable, language-agnostic foundational & intermediate programming concepts with practical analogies and code examples.

---

## Structure & Modules

### Stage 1: Core Execution & Memory Basics (Simple)

- `compiled-vs-interpreted.md` — Ahead-of-time compilation vs bytecode interpretation, JIT basics, tradeoffs.
- `stack-heap-and-stack-overflow.md` — Stack (LIFO frames) vs Heap (dynamic storage), plate-stack analogy, recursion overflow.
- `value-vs-reference-and-pointers.md` — Copying values vs sharing references, pointers explained simply, mutability traps.
- `garbage-collection-basics.md` — Manual vs automatic memory management, reference counting and mark-and-sweep mental models.

### Stage 2: Data Types, Functions & Scope (Easy–Medium)

- `type-systems-static-vs-dynamic.md` — Compile-time vs runtime checks, strong vs weak coercion, handling null/nil safely.
- `scope-closures-and-callbacks.md` — Variable scope, first-class functions, callbacks, closures (functions with a backpack).
- `recursion-vs-iteration.md` — Base cases, recursive call stacks, nested trees vs loops, stack safety.

### Stage 3: Structuring Code & Design Paradigms (Medium)

- `programming-paradigms.md` — Procedural vs Object-Oriented vs Functional styles compared with simple examples.
- `composition-vs-inheritance-and-interfaces.md` — "Has-a" vs "Is-a", composition over inheritance, interfaces as contracts.
- `error-handling-patterns.md` — Exceptions (try/catch) vs explicit error values (Go err != nil), failure handling.
- `generics-basics.md` — Reusable type-safe functions and data structures without boilerplate.

### Stage 4: Everyday Runtime & Backend Bridge (Medium)

- `sync-vs-async-programming.md` — Blocking vs non-blocking I/O, the restaurant buzzer analogy, async/await.
- `processes-threads-and-coroutines.md` — Separate houses (processes) vs roommates (threads) vs cooperative fibers (coroutines/goroutines).
- `serialization-and-encoding-basics.md` — Converting in-memory objects to text/bytes (JSON, YAML, Protobuf, UTF-8).

---

## Hub & Navigation Updates

- Update `content/Architecture/programming-concepts/README.md` with links to all 14 modules.
- Update `content/Architecture.md` to link to the updated section and modules.
