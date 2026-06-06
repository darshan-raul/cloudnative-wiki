---
title: Memory Leaks
tags: [performance, debugging, production]
date: 2025-05-24
description: How memory leaks happen in production systems and how to detect them
---

# Memory Leaks

A memory leak is memory **allocated but no longer referenced** — the garbage collector can't free it because something still holds a reference, or the code forgot to release it.

In long-running processes (servers, agents, batch jobs), leaks compound until the process runs out of memory and crashes.

---

## ELI5

```
You ask the kitchen for a plate → they give you one → you eat, but
NEVER return the plate.
Eventually the kitchen has no plates left → can't serve anyone → crash.
```

In code: you `malloc()` but never `free()`. Or in GC'd languages, you hold references to objects you no longer need.

---

## Common Causes

### 1. Unbounded Caches

```python
# ❌ Leaky: cache grows forever
cache = {}

def get_user(user_id):
    if user_id not in cache:
        cache[user_id] = db.fetch_user(user_id)
    return cache[user_id]
```

**Fix:** Use `functools.lru_cache` with max size, or TTL-based cache.

```python
# ✅ Fixed: bounded LRU cache
from functools import lru_cache

@lru_cache(maxsize=1000)
def get_user(user_id):
    return db.fetch_user(user_id)
```

### 2. Event Listener Accumulation

```javascript
// ❌ Leaky: new listener added on every request
app.get('/subscribe', (req, res) => {
  eventEmitter.on('update', () => {
    res.send('notification');
  });
});
```

**Fix:** Remove listener when done, or use a once-off pattern.

```javascript
// ✅ Fixed: one-time listener
eventEmitter.once('update', () => {
  res.send('notification');
});
```

### 3. Global State Accumulators

```python
# ❌ Leaky: list grows unbounded
connected_users = []

def on_user_connect(user):
    connected_users.append(user)  # never removed
```

**Fix:** Use a bounded structure or explicitly manage lifecycle.

### 4. Closures Holding References

```python
# ❌ Leaky: closure captures large object permanently
def create_handler(large_dataframe):
    def handler(request):
        return process(large_dataframe)  # large_dataframe lives as long as handler
    return handler
```

**Fix:** Don't capture large objects in closures if the closure outlives the use case.

### 5. Connection Pools Not Closed

```python
# ❌ Leaky: connection opened, never closed
def get_data():
    conn = psycopg2.connect(DATABASE_URL)
    return conn.execute("SELECT * FROM events")
    # conn.close() never called
```

**Fix:** Context manager or finally block.

```python
# ✅ Fixed
def get_data():
    with psycopg2.connect(DATABASE_URL) as conn:
        return conn.execute("SELECT * FROM events")
```

---

## Detection

### Python

```bash
# Tracemalloc — find memory allocation by line
python -m tracemalloc -m tracemalloc start

# Or in prod: objgraph
pip install objgraph
python -c "
import objgraph
objgraph.show_most_common_types(limit=20)
"
```

### Go

```bash
# pprof — heap profiling
go tool pprof http://localhost:6060/debug/pprof/heap
```

### Process-level (Linux)

```bash
# Watch RSS of a process over time
pidstat -r -p $(pgrep -f myservice) 1

# Or
while true; do
  echo "$(date): $(ps -o rss= -p $(pgrep -f myservice)) KB"
  sleep 10
done
```

---

## Prevention Checklist

```
□ Bounded caches (LRU with maxsize, or TTL eviction)
□ Event listeners removed when no longer needed
□ Global state has explicit lifecycle management
□ Closures don't capture large/heavy objects
□ DB connections use context managers (with block)
□ Background jobs / agents have max lifetime + restart policy
□ Health checks include memory metrics
□ Crash-only design: OOM kills process, orchestrator restarts
```

---

## Architecture Impact

For solution architects, memory leaks in **data plane components** (sidecar proxies, agents, middleware) are higher severity than in batch workers — they cause cascading failures.

```
                    ┌─────────────┐
Service A ─────────▶│   Envoy     │ ◀── leak here = all services affected
                    │  (sidecar)  │
                    └─────────────┘
```

**K8s:** Set resource limits. Let OOMKilled restart the pod rather than leak indefinitely.

```yaml
resources:
  limits:
    memory: 256Mi  # pod dies and restarts on leak, doesn't starve others
```

---

## Source

- [Python tracemalloc docs](https://docs.python.org/3/library/tracemalloc.html)
- [Go pprof Heap](https://pkg.go.dev/net/http/pprof)
