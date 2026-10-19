---
title: "FastAPI Production: Lifespan, Middleware, Async DB, and Auth"
description: "Master production FastAPI architecture: full request lifecycle sequence diagram, lifespan context managers, async SQLAlchemy 2.0 with expire_on_commit=False, and JWT authentication."
tags:
  - architecture
  - languages
  - python
  - fastapi
  - production
date: 2026-10-19
aliases:
  - Architecture/languages/python/fastapi-production-middleware-async-db-and-auth
---

# FastAPI Production: Lifespan, Middleware, Async DB, and Auth

Building production-grade microservices with FastAPI requires understanding the complete HTTP request/response pipeline, managing database connection pools with async SQLAlchemy 2.0, and enforcing authentication.

---

## 1. Complete FastAPI Request Lifecycle

Understanding the exact sequence of events for every incoming request prevents subtle bugs with middleware, database transactions, and background tasks:

```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant Middleware as ASGI Middleware
    participant DI as Depends() Injector
    participant Route as Route Handler
    participant DB as Async DB Session
    participant BG as BackgroundTasks

    Client->>Middleware: HTTP Request (headers, body)
    Middleware->>Middleware: Inject X-Request-ID & start latency timer
    Middleware->>DI: Resolve Dependencies
    DI->>DB: Open AsyncSessionLocal()
    DI->>Route: Call handler with active session & auth user
    Route->>DB: Execute async queries (await session.execute)
    Route-->>DI: Return domain object
    DI->>DI: Validate & serialize with response_model
    DI->>DB: Commit / Rollback session (in yield dependency)
    DI-->>Middleware: Transmit HTTP Response
    Middleware->>Middleware: Attach timing headers (X-Process-Time)
    Middleware-->>Client: Return HTTP Response to Client
    Middleware->>BG: Execute BackgroundTasks (detached from response!)
```

---

## 2. Application Lifecycle Management (`lifespan`)

FastAPI uses an asynchronous context manager (`lifespan`) to manage startup and shutdown state. This replaces deprecated `@app.on_event("startup")`:

```python
import contextlib
from fastapi import FastAPI
import httpx

app_resources = {}

@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    # STARTUP: Initialize connection pools before accepting any HTTP traffic
    print("[STARTUP] Initializing async HTTP client and cache connections...")
    app_resources["http_client"] = httpx.AsyncClient(timeout=10.0)

    yield  # The application serves incoming requests while yielding here

    # SHUTDOWN: Gracefully close connections and drain pools upon SIGTERM
    print("[SHUTDOWN] Closing async HTTP client and releasing connection pools...")
    await app_resources["http_client"].aclose()

app = FastAPI(title="Production Gateway", lifespan=lifespan)
```

---

## 3. Asynchronous SQLAlchemy 2.0 and the `expire_on_commit=False` Trap

Integrating SQLAlchemy 2.0 in async mode requires explicit pool configuration and understanding how async ORMs handle lazy loading:

```python
from collections.abc import AsyncGenerator
from typing import Annotated
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

DATABASE_URL = "postgresql+asyncpg://postgres:secret@127.0.0.1:5432/orders_db"

# 1. Engine Configuration with connection pooling:
engine = create_async_engine(
    DATABASE_URL,
    pool_size=20,           # Persistent connections in pool
    max_overflow=10,        # Burst connections beyond pool_size
    pool_recycle=1800,      # Recycle connections after 30m to avoid stale drops
    echo=False,
)

# 2. Session Factory:
# CRITICAL: 'expire_on_commit=False' is MANDATORY in async SQLAlchemy!
# In sync mode, commit() expires all object attributes, triggering implicit SELECT queries
# on next attribute access. In async mode, implicit I/O is impossible, causing the fatal:
# 'sqlalchemy.exc.MissingGreenlet: greenlet_spawn has not been called' crash!
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)

class Base(DeclarativeBase):
    pass

class Order(Base):
    __tablename__ = "orders"
    id: Mapped[int] = mapped_column(primary_key=True)
    customer_id: Mapped[str]
    total_cents: Mapped[int]

# 3. Dependency providing an isolated session with auto-rollback per request:
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise

DBSession = Annotated[AsyncSession, Depends(get_db)]
```

---

## 4. BackgroundTasks vs. Distributed Message Queues

FastAPI's built-in `BackgroundTasks` runs tasks in the background **after** the response is sent:

```python
from fastapi import BackgroundTasks

def send_audit_log(event: str, order_id: int):
    # Runs in a background worker thread after the response has left the server
    print(f"[AUDIT] Event {event} recorded for order #{order_id}")

@app.post("/orders/{order_id}/checkout")
async def checkout_order(order_id: int, bg_tasks: BackgroundTasks):
    bg_tasks.add_task(send_audit_log, "CHECKOUT_COMPLETED", order_id)
    return {"status": "Order accepted"}
```

> [!WARNING]
> **Production Decision Matrix:**
>
> - **Use `BackgroundTasks` for:** Quick, fire-and-forget, non-critical tasks (< 1 second) like metric emission or ephemeral webhooks.
> - **Use Celery, ARQ, or Kafka for:** Heavy computations, PDF generation, or mission-critical tasks (emails, payments). `BackgroundTasks` runs in-memory; if the Kubernetes pod restarts or crashes, all pending background tasks are **permanently lost**!

---

## 5. JWT Authentication with OAuth2 Password Bearer

```python
from datetime import datetime, timedelta, timezone
from typing import Annotated
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
import jwt

SECRET_KEY = "super-secret-signing-key"
ALGORITHM = "HS256"

# Tells Swagger UI where clients submit username/password to obtain a token:
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/token")

def create_access_token(user_id: str, expires_delta: timedelta = timedelta(hours=1)) -> str:
    expire = datetime.now(timezone.utc) + expires_delta
    payload = {"sub": user_id, "exp": expire}
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

async def get_current_user(token: Annotated[str, Depends(oauth2_scheme)]) -> dict:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
        return {"user_id": user_id}
    except jwt.PyJWTError:
        raise credentials_exception

@app.get("/users/me")
async def read_current_user(current_user: Annotated[dict, Depends(get_current_user)]):
    return {"active_user": current_user["user_id"]}
```

---

## Next Steps

- [[Architecture/languages/python/19-memory-management-gc-and-slots|19: Memory Management, GC, and Slots]] — CPython memory model and optimization.
- [[Architecture/languages/python/21-testing-pytest-mocking-and-async-tests|21: Testing with Pytest, Mocking, and Async Tests]] — End-to-end API integration tests.
