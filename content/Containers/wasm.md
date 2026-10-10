---
title: WebAssembly on the Server
tags: [containers, wasm, webassembly, wasi, runtimes]
date: 2026-10-10
description: WebAssembly as a server-side sandbox — what a Wasm module is, WASI and the component model, how it compares with containers, running Wasm in Docker and Kubernetes through containerd shims, and where it is and is not a good fit today.
---

# WebAssembly on the Server

WebAssembly (Wasm) is a portable binary instruction format, originally designed to run code safely in browsers. The same properties — a small, fast, sandboxed unit of code that runs on any CPU — make it interesting on servers, where it sits next to containers rather than replacing them.

## What a Wasm module is

A `.wasm` file is compiled code for a virtual stack machine. A **runtime** (Wasmtime, WasmEdge, Wasmer, wazero) loads it and compiles it to native code. Three properties define it:

- **Portable.** One binary runs on x86, Arm and anything else with a runtime. There is no per-architecture build.
- **Sandboxed by default.** A module has its own linear memory and can do nothing except compute. It has no access to files, network, clock or environment unless the host explicitly grants a capability.
- **Small and fast to start.** Modules are often kilobytes to a few megabytes and instantiate in microseconds to milliseconds.

## WASI and the component model

Pure Wasm has no system interface. **WASI** (the WebAssembly System Interface) defines standard ways for a module to ask the host for files, sockets, clocks and random numbers. It is capability-based: the host hands the module a handle to one directory, not the filesystem.

| Version        | Adds                                                                       |
| :------------- | :------------------------------------------------------------------------- |
| WASI Preview 1 | A POSIX-like set of calls: files, clocks, random, arguments, environment   |
| WASI 0.2       | The **component model**, typed interfaces written in WIT, HTTP and sockets |
| WASI 0.3       | Native asynchronous I/O in the component model                             |

The **component model** is the more significant idea. A component declares typed imports and exports, so components written in different languages can be linked together without sharing memory or agreeing on an ABI — a Rust image filter called from a Python handler, with the boundary checked by the runtime.

## Compared with containers

|                        | Linux container                                                      | Wasm module                                                |
| :--------------------- | :------------------------------------------------------------------- | :--------------------------------------------------------- |
| Isolation boundary     | Kernel [[Containers/namespaces-and-cgroups\|namespaces and cgroups]] | The Wasm runtime's sandbox                                 |
| Default access         | A full Linux user space, minus what is dropped                       | Nothing, until granted                                     |
| Portability            | Per OS and architecture; multi-arch images                           | One binary everywhere                                      |
| Artifact size          | Megabytes to gigabytes                                               | Kilobytes to megabytes                                     |
| Cold start             | Hundreds of milliseconds to seconds                                  | Microseconds to milliseconds                               |
| Compatibility          | Runs unmodified Linux software                                       | Code must be compiled for Wasm; many libraries do not work |
| Threads, sockets, GPUs | Yes                                                                  | Partial and evolving                                       |
| Ecosystem maturity     | Very high                                                            | Young                                                      |

Solomon Hykes's well-known remark — that Docker would not have been needed had Wasm and WASI existed in 2008 — captures the appeal. The compatibility row captures why containers are not going away.

## Language support

| Language                 | State                                                                         |
| :----------------------- | :---------------------------------------------------------------------------- |
| Rust, C, C++, Zig        | First-class; small binaries                                                   |
| Go                       | Standard toolchain targets WASI; TinyGo produces smaller modules              |
| JavaScript, Python, Ruby | The interpreter itself is compiled to Wasm and bundled — larger, slower start |
| C#, Java, Kotlin         | Usable, with caveats that depend on garbage-collection support in the runtime |

Anything that depends on native extensions, `fork`, arbitrary system calls or mature threading needs checking first.

## Running Wasm with container tooling

Wasm slots into the existing stack at the low-level runtime layer described in [[Containers/runtimes|container runtimes]]. A **containerd shim** from the `runwasi` project runs a Wasm module instead of calling runc:

```
kubelet ─► containerd ─► containerd-shim-spin / -wasmtime / -wasmedge ─► Wasm runtime ─► module
                     └─► containerd-shim-runc-v2 ─► runc ─► Linux container     (same node, side by side)
```

Modules are packaged as OCI artifacts and stored in ordinary [[Containers/registries|registries]].

**Docker** can run them directly when the Wasm shims are enabled:

```bash
docker run --runtime=io.containerd.wasmtime.v1 --platform=wasi/wasm registry.example.com/hello-wasm:1.0
```

**Kubernetes** selects the shim with a `RuntimeClass`, exactly as for gVisor or Kata:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: wasmtime-spin
handler: spin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-wasm
spec:
  replicas: 3
  selector:
    matchLabels: { app: hello-wasm }
  template:
    metadata:
      labels: { app: hello-wasm }
    spec:
      runtimeClassName: wasmtime-spin
      containers:
        - name: app
          image: registry.example.com/hello-wasm:1.0
          command: ["/"]
```

The node needs the shim binary installed. The Kwasm operator and SpinKube automate that and add an application CRD; some managed services offer Wasm node pools. Services, ingress, autoscaling and [[Kubernetes/concepts/L03-workloads/01-pods|pods]] all work unchanged, because to Kubernetes it is just another runtime.

## Where it fits today

**Good fits**

- **Plugins and extensions.** Running untrusted or third-party code inside a host application, with tight limits. Envoy and Istio filters, policy engines, database user-defined functions, and SaaS extension points already work this way — see [[Kubernetes/guides/networking/istio|Istio]].
- **Edge and functions.** Platforms that run many tiny, short-lived handlers per request benefit most from microsecond start-up and high density.
- **Scale-to-zero services** where cold start dominates the experience.
- **Constrained devices**, where a container runtime is too heavy.

**Poor fits**

- Existing applications with large dependency trees, native libraries or heavy threading.
- Databases and other stateful, I/O-intensive systems.
- Anything where "it runs unmodified Linux software" is the requirement.

A realistic expectation: Wasm takes over the plugin and function niches and runs alongside containers in the same clusters. It is an additional tool, not a migration target for a typical microservice.

## Security notes

The sandbox is strong but not a reason to skip the usual controls:

- The runtime is the trusted computing base. Keep it patched; a runtime bug is the equivalent of a container escape.
- Grant capabilities narrowly — one directory, specific outbound hosts.
- Sign and verify modules like any other artifact ([[Containers/registries|registries]]).
- Network policy, resource limits and admission policy still apply at the pod level.

## Related

- [[Containers|Containers hub]]
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing|Runtime sandboxing]]
- [[Containers/images-and-layers|Images and layers]] — OCI artifacts
- [[Linux/security/seccomp|seccomp]] — the syscall-filtering approach Wasm avoids needing
- [WebAssembly on the server — wasi.dev](https://wasi.dev/)

## Further reading

- [Docker + WASM (video)](https://www.youtube.com/watch?v=bzBkrV-0c6U)
- [Kubernetes + WASM (video)](https://www.youtube.com/watch?v=oVGpoEyXgYI)
- [WASM (video)](https://www.youtube.com/watch?v=bPDbXPFFI9w)
