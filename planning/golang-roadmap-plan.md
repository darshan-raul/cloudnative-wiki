# Golang Roadmap Plan

**Date:** 2026-10-19  
**Status:** Completed  
**Scope:** `content/Architecture/languages/golang/`  
**Target Audience:** Cloud-native software engineers, backend developers, and systems architects wanting practical, code-heavy, idiomatic Go guides with runnable snippets and production gotchas.  
**Benchmark Parity:** 100% coverage of all 85 topics on [gobyexample.com](https://gobyexample.com/).

---

## 4-Stage Progressive Curriculum & Complete Topic Map (26 Numbered Modules)

### Stage 1: Go Foundations, Control Flow & Data Structures

- `01-variables-constants-and-control-flow.md` — Values, variables, constants, for loops (4 styles), if/else (short statements), switch (tagless/multi-case), enums (`iota`).
- `02-functions-pointers-and-strings.md` — Function signatures, multiple return values, variadic functions, recursion, pointers in Go (`*` and `&`), strings vs runes (UTF-8), ranging over built-ins.
- `03-modules-and-packages.md` — `go.mod`, `go.sum`, visibility, project layout (`cmd/`, `internal/`), standard build commands.
- `04-slices-and-maps.md` — Arrays vs slices, `make`, `append`, sub-slicing gotchas, comma-ok map idiom, map deletion.
- `05-structs-and-embedding.md` — Struct definitions, constructor pattern, functional options, struct embedding (composition).
- `06-methods.md` — Value vs pointer receivers, mutating vs non-mutating, nil receiver methods.
- `07-closures.md` — Closures, lexical scope, `defer` LIFO order, cleanup patterns, Go 1.22 loop variable capture.

### Stage 2: Interfaces, Type Safety, Errors & Iterators

- `08-interfaces.md` — Implicit satisfaction, `io.Reader`/`io.Writer`, interface composition, dependency injection, nil interface pitfall.
- `09-type-assertion.md` — Comma-ok type assertions, type switches (`switch v := x.(type)`), `any` alias.
- `10-error-handling.md` — Sentinel errors, error wrapping (`fmt.Errorf %w`), `errors.Is()`, `errors.As()`, panic & recover guidelines.
- `11-generics.md` — Type parameters `[T any]`, constraints (`cmp.Ordered`), generic collections, Sorting (`slices.Sort`, `slices.SortFunc`), Range over Iterators (`iter.Seq`, `iter.Seq2`).
- `12-strings-templates-and-regex.md` — String functions (`strings`), string formatting (`fmt` verbs), text templates (`text/template`), regular expressions (`regexp`).

### Stage 3: Concurrency, Timers, Rate Limiting & Synchronization

- `13-concurrency-architecture.md` — Channels vs Mutexes decision matrix, Go concurrency philosophy.
- `14-channels.md` — Directional channels, buffered vs unbuffered, range & close, select, non-blocking channel operations (`select default`), worker pools, pipelines.
- `15-sync-and-atomic.md` — `sync.Mutex`, `sync.RWMutex`, `sync.WaitGroup`, `sync.Once`, `sync/atomic` (Atomic Counters), `errgroup.Group`, race detector (`go test -race`).
- `16-timers-tickers-and-rate-limiting.md` — Timers (`time.NewTimer`), Tickers (`time.NewTicker`), Rate Limiting (bursty token buckets), Stateful Goroutines (actor model with channels).
- `17-context.md` — `context.Background()`, `TODO()`, timeouts, cancellation, value propagation, HTTP request tracing.

### Stage 4: Practical Backend, Standard Library, OS & Production Go

- `18-time-numbers-urls-and-crypto.md` — Time, epoch, time formatting/parsing (`2006-01-02 15:04:05`), random numbers (`math/rand/v2`, `crypto/rand`), number parsing (`strconv`), URL parsing (`net/url`), SHA256 hashes, Base64 encoding.
- `19-files-directories-and-embed.md` — Reading files, writing files, line filters (`bufio.Scanner`), file paths (`filepath`), directories, temporary files/directories, embed directive (`//go:embed`).
- `20-cli-env-and-logging.md` — Command-line arguments (`os.Args`), command-line flags (`flag`), command-line subcommands (`flag.NewFlagSet`), environment variables (`os.Getenv`), structured logging (`log/slog`).
- `21-os-processes-and-exec.md` — Spawning processes (`os/exec`), exec'ing processes (`syscall.Exec`), signals, program exit (`os.Exit`).
- `22-json-and-struct-tags.md` — `json.Marshal`/`Unmarshal`, struct tags, omitempty, custom marshaling, streaming decoders, XML (`encoding/xml`).
- `23-http-and-graceful-shutdown.md` — HTTP Client (`http.Client`), TCP Server (`net.Listen`), Go 1.22 routing (`http.ServeMux`), middleware, timeouts, OS signal handling and graceful shutdown.
- `24-validators.md` — `go-playground/validator`, struct tags, custom validators, returning client errors.
- `25-reflect.md` — `reflect.Type`, `reflect.Value`, field inspection, tag extraction, reflection trade-offs.
- `26-testing-and-benchmarks.md` — Table-driven tests, `t.Run`, subtests, `httptest`, benchmarks (`b.N`).

---

## Hub & Navigation Status

- `content/Architecture/languages/golang/index.md` titled **Golang** acts as the root roadmap page linking all 26 numbered modules in progressive sequence, with an exhaustive Go by Example topic coverage matrix.
