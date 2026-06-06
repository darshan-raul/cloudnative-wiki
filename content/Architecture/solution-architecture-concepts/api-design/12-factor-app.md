---
title: 12-Factor App
tags: [architecture, cloud-native, microservices]
date: 2025-05-24
description: Heroku's methodology for building cloud-native SaaS applications
---

# 12-Factor App

A methodology for building **Software-as-a-Service (SaaS)** applications that are:
- **Portable** across cloud providers
- **Scalable** without significant re-architecture
- **Deployable** in CI/CD pipelines

Originally published by Heroku (2011). Still the foundation of cloud-native patterns today.

---

## The 12 Factors

###1. Codebase — One repo, many deployments
One codebase tracked in git, deployed to many environments (dev, staging, prod).

```
# Each environment is a separate "release"
git clone https://github.com/myorg/api
# prod release
git checkout v2.1.0
# dev release
git checkout main
```

### 2. Dependencies — Explicitly declare and isolate
Never rely on system-wide packages. Use a lockfile.

```bash
# Python
pip freeze > requirements.txt

# Node.js
npm ci  # uses package-lock.json

# Go
go mod tidy
```

### 3. Config — Store config in the environment
Credentials and env-specific settings belong in env vars, **never in code**.

```python
# ❌ Bad: hardcoded
DB_PASSWORD = "secret123"

# ✅ Good: from environment
DB_PASSWORD = os.getenv("DB_PASSWORD")
```

### 4. Backing Services — Treat as attached resources
Databases, queues, caches — all are **attached resources** via config, not hardcoded URLs.

```python
# ✅ Same code, different env var
REDIS_URL = os.getenv("REDIS_URL")  # points to local or cloud
```

### 5. Build, Release, Run — Strict separation
```
Build →  Release →  Run
 .tar    + config   process
```
Never modify code at runtime. A release is **immutable**.

### 6. Processes — Stateless, no shared state
Any needed state goes to a backing service (Redis, DB, S3).

```python
# ❌ Bad: process-level memory cache
cache = {}

# ✅ Good: external store
cache = redis.get(f"user:{user_id}")
```

### 7. Port Binding — Self-contained, no runtime injection
The app **exports HTTP as a service** — no embedded web servers injected at deploy time.

```python
# FastAPI — self-contained
app = FastAPI()
# Runs on the port env var declares
```

### 8. Concurrency — Scale out via process model
Don't scale up (bigger VM). Scale out (more processes).

```yaml
# docker-compose.yml — same binary, multiple processes
services:
  web:
    deploy:
      replicas: 4
  worker:
    deploy:
      replicas: 8
```

### 9. Disposability — Fast startup, graceful shutdown
Apps must start in seconds and handle SIGTERM gracefully.

```python
import signal, sys

def graceful_shutdown(signum, frame):
    # Close DB connections, flush buffers, exit cleanly
    db.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, graceful_shutdown)
```

### 10. Dev/Prod Parity — Keep dev and prod similar
The gap between dev and prod is where most breakage happens.

| Gap | Fix |
|-----|-----|
| Different languages | Use Docker containers |
| Different DB | Use Testcontainers |
| Different env vars | Use `.env` files |

### 11. Logs — Treat as event streams
Don't write to files. Emit to stdout — let the execution environment capture.

```python
# ❌ Bad: write to file
logging.basicConfig(filename="app.log")

# ✅ Good: stdout
logging.basicConfig(stream=sys.stdout)
```

### 12. Admin Processes — Run admin/maintenance as one-off processes
Same environment, same codebase as foreground processes.

```bash
# Migrations as a one-off process
kubectl run migration \
  --image=myapp:latest \
  -- python manage.py migrate
```

---

## Quick Reference

| Factor | Key Point |
|--------|-----------|
| Codebase |1 repo → N deployments |
| Dependencies | Lockfile + isolation |
| Config | Env vars, not code |
| Backing Services | Attached via config |
| Build/Release/Run | Immutable releases |
| Processes | Stateless |
| Port Binding | Self-contained |
| Concurrency | Scale out (not up) |
| Disposability | Fast + graceful shutdown |
| Dev/Prod Parity | Minimize the gap |
| Logs | stdout event stream |
| Admin | Same env as app |

---

## Why It Matters for Solution Architecture

When evaluating a proposed architecture, the 12-factor checklist is a **fast sanity filter**:

```
Can this app:
□ Deploy independently per environment?
□ Scale horizontally without shared state?
□ Start and stop in seconds?
□ Log to stdout for centralized collection?
□ Treat all backing services as external config?
```
If any answer is no — you have an architectural debt item for the ADR.

> **Source:** [12factor.net](https://12factor.net)
