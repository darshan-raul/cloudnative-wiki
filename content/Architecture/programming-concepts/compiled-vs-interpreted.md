---
title: "Compiled vs Interpreted Languages & How Code Runs"
description: "How computer code actually executes — source code to machine code, bytecode virtual machines, JIT compilation, and practical developer trade-offs."
tags:
  - architecture
  - programming-concepts
  - compilers
  - runtimes
date: 2026-10-19
---

# Compiled vs Interpreted Languages & How Code Runs ⚙️

Computers cannot directly understand Python, Go, or JavaScript. A CPU only understands native **machine code** (streams of `0`s and `1`s encoding binary CPU instructions like `MOV`, `ADD`, `JMP`).

The difference between programming languages comes down to **when and how** your human-readable source code is translated into machine instructions.

---

## 1. The Real-World Analogy: Book Translation

Imagine you have a book written in Spanish and you need an English speaker to read it:

1. **Compiled (Ahead-of-Time):** A translator sits down before publication day and translates the entire book into English, printing a complete English edition. When an English reader gets it, they read it immediately at full speed with no translator in the room.
2. **Interpreted:** A human translator stands next to the English reader, reading one Spanish sentence, translating it on the spot into English, and waiting for the reader before translating the next sentence.
3. **Just-In-Time (JIT / Hybrid):** The translator translates sentence by sentence at first, but whenever they notice a sentence or paragraph being read repeatedly (a "hot loop"), they write down the English translation on a cheat sheet so they never have to re-translate it again.

---

## 2. The Three Execution Models

```mermaid
flowchart TD
    subgraph Compiled["1. Ahead-of-Time (AOT) Compiled (Go, Rust, C, C++)"]
        Src1["Source Code (.go, .rs)"] --> Comp1["Compiler (go build / rustc)"]
        Comp1 --> Bin1["Single Binary Executable (Machine Code)"]
        Bin1 --> Run1["CPU runs directly (Instant startup, fast)"]
    end

    subgraph Interpreted["2. Bytecode Interpreted (Python, Ruby, PHP)"]
        Src2["Source Code (.py)"] --> Comp2["Lightweight Parser"]
        Comp2 --> Byte2["Intermediate Bytecode (.pyc)"]
        Byte2 --> VM2["Virtual Machine / Interpreter (ceval.c)"]
        VM2 --> Run2["CPU executes interpreter instructions"]
    end

    subgraph Hybrid["3. Bytecode VM + JIT (Java, C#, Node.js / JavaScript)"]
        Src3["Source Code (.java, .js)"] --> Byte3["Bytecode (.class / V8 bytecode)"]
        Byte3 --> JIT3["Runtime JIT Engine (HotSpot / V8 TurboFan)"]
        JIT3 -->|Compiles hot code on the fly| Run3["CPU executes native machine code"]
    end
```

### Trade-Off Comparison

| Dimension              | Compiled (AOT)                                         | Interpreted                                          | Bytecode + JIT                                         |
| :--------------------- | :----------------------------------------------------- | :--------------------------------------------------- | :----------------------------------------------------- |
| **Examples**           | Go, Rust, C, C++, Zig                                  | Python (CPython), Ruby                               | Java (JVM), C# (.NET), JavaScript (V8)                 |
| **Speed / Throughput** | ⚡ Fastest (native machine instructions)               | 🐢 Slower (10x–30x CPU overhead)                     | ⚡ Fast (approaches native once warmed up)             |
| **Startup Time**       | ⚡ Instant (milliseconds)                              | ⚡ Fast (starts interpreting immediately)            | ⏳ Slower (warmup / JIT compilation phase)             |
| **Deployment**         | 📦 Single static binary (no dependencies)              | 📂 Source files + language runtime installed         | 📂 Bytecode archive (`.jar`) + runtime (JRE/Node)      |
| **Portability**        | Target-specific (need to compile for Linux ARM vs x86) | Highly portable (runs wherever runtime is installed) | "Write once, run anywhere" (VM abstracts OS)           |
| **Error Timing**       | Syntax & type errors caught **at compile time**        | Errors often caught **when line executes**           | Hybrid (compiler catches syntax, runtime catches rest) |

---

## 3. What is Bytecode and Virtual Machines?

Languages like Java, Python, and JavaScript don't jump directly from source code to machine code. They use a middle step called **Bytecode**:

```
Source Code (add.py) ──▶ Bytecode (.pyc) ──▶ Virtual Machine (Python runtime) ──▶ Machine Code (CPU)
   a + b                   BINARY_ADD                    C implementation                 01101001...
```

- **Why Bytecode?** It makes languages portable. The Python or Java compiler creates bytecode once. As long as a computer has the Python runtime or Java Virtual Machine (JVM) installed, the same bytecode runs on Windows, macOS, and Linux without changing a line of code.

---

## 4. Why This Matters for Cloud & Backend Systems

When building modern microservices, APIs, and cloud-native applications:

1. **Container Sizes & Security:** A compiled Go or Rust program compiles into a single binary that can run in an empty `scratch` or `distroless` container (10–25 MB total). An interpreted Python or Node.js container requires the OS libraries, interpreter, and `node_modules` or `site-packages` (150–500 MB+).
2. **Serverless (Cold Starts):** In AWS Lambda or Google Cloud Functions, compiled languages (Go, Rust) start in ~10–20 milliseconds. Heavy JVM or complex Python apps can take seconds to initialize on cold starts.
3. **Developer Velocity:** Interpreted languages shine during development: edit a line of code in Python or Node.js and refresh instantly—no waiting for a long compilation step.

---

## Across the Wiki

- [[Architecture/programming-concepts/stack-heap-and-stack-overflow|Stack vs Heap Memory Layout]] — Where variables live once your program executes.
- [[Architecture/programming-concepts/garbage-collection-basics|Garbage Collection Basics]] — How runtimes clean up memory automatically.
- [[Architecture/languages/golang/README|Go Systems Architecture]] — Deep dive into Go compilation and cloud-native tools.
- [[Architecture/languages/python/README|Python Production Engineering]] — Python runtime and modern packaging standards.
