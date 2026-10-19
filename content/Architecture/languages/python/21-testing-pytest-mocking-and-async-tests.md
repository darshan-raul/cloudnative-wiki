---
title: "Python Testing: Pytest, Mocking, and Async Tests"
description: "Master modern Python testing: pytest fixture scopes, parametrization, the #1 patch-location mocking rule, AsyncMock, and testing FastAPI with AsyncClient and dependency overrides."
tags:
  - architecture
  - languages
  - python
  - testing
date: 2026-10-19
aliases:
  - Architecture/languages/python/testing-pytest-mocking-and-async-tests
---

# Python Testing: Pytest, Mocking, and Async Tests

Writing fast, reliable tests requires understanding `pytest` fixture scopes, knowing where and how to patch external dependencies without leaking mocks, and testing asynchronous web services cleanly.

---

## 1. Fixture Scopes and Lifecycle in `conftest.py`

`pytest` fixtures use dependency injection. A test declares what it needs as arguments, and `pytest` resolves them. Scopes determine how often a fixture executes:

| Scope                    | Frequency                                  | Best Suited For                                                         |
| :----------------------- | :----------------------------------------- | :---------------------------------------------------------------------- |
| **`function`** (default) | Runs before & after **each test function** | Isolated database transactions, temporary files, clean mock state       |
| **`class`**              | Runs once per test class                   | Grouped tests sharing read-only state                                   |
| **`module`**             | Runs once per test `.py` file              | Expensive fixtures shared within a single test module                   |
| **`session`**            | Runs **once across the entire test run**   | Starting Docker containers (Testcontainers), global DB connection pools |

```python
# conftest.py
import pytest
from collections.abc import Generator

@pytest.fixture(scope="session")
def global_db_engine():
    # Setup runs ONCE for the entire pytest execution:
    print("\n[GLOBAL] Initializing test database connection pool...")
    engine = {"pool": "connected", "dsn": "postgres://localhost:5432/test_db"}
    yield engine
    # Teardown runs when all tests complete:
    print("\n[GLOBAL] Dropping test database connection pool.")

@pytest.fixture(scope="function")
def db_session(global_db_engine) -> Generator[dict, None, None]:
    # Setup runs before EACH test function:
    session = {"engine": global_db_engine["dsn"], "txn_id": "active_txn"}
    print("\n  [TXN] Beginning isolated transaction...")
    yield session
    # Teardown rolls back changes:
    print("  [TXN] Rolling back transaction (clean state preserved).")
```

---

## 2. Table-Driven Tests with `@pytest.mark.parametrize`

Parametrization runs the exact same test logic across multiple input/output fixtures without duplicating test functions:

```python
import pytest

def calculate_tier_discount(price: float, tier: str) -> float:
    discounts = {"bronze": 0.0, "silver": 0.10, "gold": 0.20}
    if tier not in discounts:
        raise ValueError(f"Unknown tier: {tier}")
    return price * (1.0 - discounts[tier])

@pytest.mark.parametrize("price,tier,expected_price", [
    (100.0, "bronze", 100.0),
    (100.0, "silver", 90.0),
    (100.0, "gold", 80.0),
    (50.0,  "gold", 40.0),
])
def test_discounts(price, tier, expected_price):
    assert calculate_tier_discount(price, tier) == expected_price

def test_invalid_tier_raises_error():
    # Verify expected exceptions cleanly:
    with pytest.raises(ValueError, match="Unknown tier: platinum"):
        calculate_tier_discount(100.0, "platinum")
```

---

## 3. The #1 Python Mocking Gotcha: Where to Patch

The single most common source of broken tests in Python is patching an object in the wrong module:

> [!CRITICAL]
> **The Golden Patch Rule:**  
> **Patch where an object is _LOOKED UP / IMPORTED_, NOT where it is originally _DEFINED_!**

### The Scenario:

Imagine `src/services/billing.py` has:

```python
# src/services/billing.py
import requests

def charge_customer(card_id: str):
    return requests.post("https://api.stripe.com/charge", json={"card": card_id})
```

### The Test:

```python
from unittest.mock import patch

# ❌ WRONG: Patching requests where it was defined!
# with patch("requests.post") ... (billing.py already imported its own local reference!)

# ✅ CORRECT: Patch requests inside the module that uses it:
@patch("src.services.billing.requests.post")
def test_charge_customer(mock_post):
    mock_post.return_value.status_code = 200
    mock_post.return_value.json.return_value = {"charge_id": "ch_123"}

    from src.services.billing import charge_customer
    response = charge_customer("card_xyz")
    assert response.status_code == 200
```

---

## 4. Mocking Strategies Comparison Matrix

| Tool                               | Scope                       | Best Used For                                                        | Trade-Off                                   |
| :--------------------------------- | :-------------------------- | :------------------------------------------------------------------- | :------------------------------------------ |
| **`unittest.mock.patch`**          | Context manager / Decorator | Mocking third-party functions, external HTTP clients, and libraries  | String import path can be typo-prone        |
| **`pytest.monkeypatch`**           | Function fixture            | Modifying `os.environ`, `sys.argv`, and dictionary keys during tests | Manual restore logic, slightly more verbose |
| **`FastAPI dependency_overrides`** | Application DI engine       | Swapping real DB sessions or Auth services with mock repositories    | Only applies to FastAPI dependency trees    |

---

## 5. Testing FastAPI Endpoints with `httpx.AsyncClient` & Overrides

Test asynchronous FastAPI endpoints in-memory without starting live TCP network ports:

```python
import pytest
from httpx import ASGITransport, AsyncClient
from fastapi import FastAPI, Depends

app = FastAPI()

# Real production dependency:
def get_user_repository():
    return "production_postgresql_repository"

@app.get("/users/{user_id}")
def get_user(user_id: int, repo=Depends(get_user_repository)):
    return {"user_id": user_id, "source": repo}

@pytest.mark.asyncio
async def test_get_user_endpoint():
    # 1. Inject mock dependency:
    app.dependency_overrides[get_user_repository] = lambda: "mock_in_memory_repo"

    # 2. Test ASGI app in-memory using ASGITransport (super fast!):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        response = await client.get("/users/42")

    # 3. Always clean up dependency overrides to prevent test leakage:
    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == {"user_id": 42, "source": "mock_in_memory_repo"}
```

---

## Next Steps

- [[Architecture/languages/python/22-logging-cli-and-os-processes|22: Logging, CLI, and OS Processes]] — Structured logging and process management.
- [[Architecture/languages/python/24-production-packaging-docker-and-deployment|24: Production Packaging, Docker, and Deployment]] — Running pytest in CI and Docker pipelines.
