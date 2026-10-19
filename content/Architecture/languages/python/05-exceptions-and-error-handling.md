---
title: "Python Exceptions and Error Handling"
description: "Master Python's error handling: try/except/else/finally execution order, EAFP vs LBYL, exception chaining with raise from and __cause__, custom hierarchies, and Python 3.11+ ExceptionGroup."
tags:
  - architecture
  - languages
  - python
  - error-handling
date: 2026-10-19
aliases:
  - Architecture/languages/python/exceptions-and-error-handling
---

# Python Exceptions and Error Handling

In Python, exceptions are not reserved exclusively for fatal errors; they are a fundamental part of standard control flow and language idioms.

---

## 1. The Execution Lifecycle: `try / except / else / finally`

Understanding the exact execution lifecycle prevents subtle resource leaks and masked bugs:

```python
def execute_transaction(account_id: str, amount: float) -> str:
    print("\n--- Starting Transaction ---")
    try:
        # Step 1: Code that might raise an exception
        print(f"Validating withdrawal of ${amount} for {account_id}...")
        if amount <= 0:
            raise ValueError("Amount must be strictly positive!")
        balance = 500.0  # Simulated balance
        if amount > balance:
            raise RuntimeError("Insufficient funds in account!")
        print("Deduction successful.")

    except ValueError as err:
        # Step 2A: Runs ONLY if a ValueError occurred
        print(f"[HANDLED] Input error: {err}")
        return "FAILED_INPUT"

    except RuntimeError as err:
        # Step 2B: Runs ONLY if a RuntimeError occurred
        print(f"[HANDLED] Business rule violation: {err}")
        return "FAILED_BALANCE"

    else:
        # Step 3: Runs ONLY if the try block completed with NO exceptions
        print("[SUCCESS] Committing ledger entry to database...")
        return "TRANSACTION_COMMITTED"

    finally:
        # Step 4: ALWAYS runs, whether exceptions occurred, were caught, or return was hit!
        print("[CLEANUP] Releasing account lock and closing audit session.")

# Case 1: Success path (try -> else -> finally)
print("Result 1:", execute_transaction("acc_101", 100.0))

# Case 2: Handled error path (try -> except -> finally)
print("Result 2:", execute_transaction("acc_101", -50.0))
```

---

## 2. The Pythonic Philosophy: EAFP vs. LBYL

- **LBYL (Look Before You Leap):** Proactively checks conditions, permissions, and keys using `if` statements before performing the operation.
- **EAFP (Easier to Ask for Forgiveness than Permission):** Assumes the valid case will succeed and catches exceptions if it fails.

```python
# LBYL Approach (Common in C/Go):
# Problems: 1) Slow (checks keys twice), 2) Race condition in multi-threaded/concurrent code
def get_port_lbyl(config: dict) -> int:
    if "port" in config and isinstance(config["port"], str) and config["port"].isdigit():
        return int(config["port"])
    return 8080

# EAFP Approach (Idiomatic Python):
# Benefits: 1) Zero overhead on the fast path, 2) Atomic operation (no race condition)
def get_port_eafp(config: dict) -> int:
    try:
        return int(config["port"])
    except (KeyError, ValueError, TypeError):
        return 8080
```

---

## 3. Custom Exception Hierarchies and Exception Chaining

Always inherit custom application exceptions from `Exception` (never `BaseException`, which would catch `KeyboardInterrupt` and `SystemExit`, preventing clean Ctrl+C exits).

### Explicit Chaining (`raise ... from err`) vs `raise ... from None`

```python
class CloudNativeError(Exception):
    """Base exception for all domain errors."""
    pass

class DatabaseConnectionError(CloudNativeError):
    """Raised when the database connection pool fails."""
    def __init__(self, host: str, port: int, original_err: str):
        super().__init__(f"Database connection to {host}:{port} failed: {original_err}")
        self.host = host
        self.port = port

import socket

def connect_to_database(host: str, port: int):
    try:
        socket.create_connection((host, port), timeout=0.1)
    except OSError as err:
        # 'raise ... from err' sets the __cause__ attribute on the new exception,
        # printing BOTH tracebacks cleanly in your APM or terminal!
        raise DatabaseConnectionError(host, port, str(err)) from err

        # Alternatively, 'raise ... from None' suppresses the original traceback
        # when wrapping sensitive internal errors from leaking to users:
        # raise DatabaseConnectionError(host, port, "Access denied") from None
```

---

## 4. `ExceptionGroup` and `except*` (Python 3.11+)

When running concurrent tasks (via `asyncio.TaskGroup` or thread executors), multiple tasks can raise exceptions simultaneously. Standard `except` can only handle one exception at a time. Python 3.11 introduced `ExceptionGroup` and the `except*` pattern to match and unpack sets of concurrent exceptions:

```python
import asyncio

async def fetch_user_profile():
    await asyncio.sleep(0.01)
    raise ValueError("Invalid user payload received")

async def sync_remote_cache():
    await asyncio.sleep(0.01)
    raise ConnectionResetError("Lost TCP connection to Redis")

async def main():
    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(fetch_user_profile())
            tg.create_task(sync_remote_cache())
    # 'except*' matches specific exception types inside the composite ExceptionGroup:
    except* ValueError as eg:
        print(f"Handled {len(eg.exceptions)} ValueError(s): {eg.exceptions}")
    except* ConnectionError as eg:
        print(f"Handled {len(eg.exceptions)} ConnectionError(s): {eg.exceptions}")

asyncio.run(main())
```

---

## Next Steps

- [[Architecture/languages/python/06-files-pathlib-and-serialization|06: Files, Pathlib, and Serialization]] — Robust file operations and JSON encoding.
- [[Architecture/languages/python/15-asyncio-and-event-loop|15: Asyncio and the Event Loop]] — Handling errors across asynchronous task groups.
