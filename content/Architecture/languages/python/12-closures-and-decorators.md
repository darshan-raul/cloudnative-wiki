---
title: "Python Closures and Decorators"
description: "Master lexical closures, late-binding closure traps, decorator syntax desugaring, import-time vs call-time execution, functools.wraps, and parameterized decorator factories."
tags:
  - architecture
  - languages
  - python
  - metaprogramming
date: 2026-10-19
aliases:
  - Architecture/languages/python/decorators
  - Architecture/languages/python/closures-and-decorators
---

# Python Closures and Decorators

In Python, functions are first-class citizens. A **closure** is a function that retains access to variables from its lexical enclosing scope even after that outer scope has finished executing. A **decorator** leverages closures to extend or wrap functions dynamically.

---

## 1. How Closures Work and the Late-Binding Trap

When an inner function references a variable from an enclosing scope, Python creates a **cell object** in `inner.__closure__` that points to that variable by reference:

```python
def make_multiplier(factor: int):
    # 'factor' is stored in a closure cell
    def multiply(x: int) -> int:
        return x * factor
    return multiply

double = make_multiplier(2)
print("Result:", double(10))  # Output: 20
print("Closure cell inspection:", double.__closure__[0].cell_contents)  # Output: 2
```

### 💥 The Classic Late-Binding Loop Trap

A notorious bug in Python occurs when creating closures inside loops:

```python
# 💥 THE BUG:
handlers = []
for i in range(3):
    handlers.append(lambda x: x + i)

# You expect [0+0, 1+1, 2+2] = [0, 2, 4], but look what happens:
print([h(0) for h in handlers])  # Output: [2, 2, 2]! Why?!

# EXPLANATION:
# The closures do NOT store the value of 'i' at the moment the lambda was created.
# They store a pointer to the variable 'i'. By the time the lambdas are called,
# the loop has finished and 'i' has the final value 2!

# ✅ THE FIX: Bind 'i' at definition time via a default argument:
clean_handlers = []
for i in range(3):
    clean_handlers.append(lambda x, step=i: x + step)

print([h(0) for h in clean_handlers])  # Output: [0, 1, 2] (Correct!)
```

---

## 2. Syntax Desugaring: Import-Time vs. Call-Time Execution

The `@` decorator syntax is pure syntactic sugar for passing a function through a higher-order callable:

```python
def log_execution(func):
    print(f"[IMPORT-TIME] Decorating function '{func.__name__}'")
    def wrapper(*args, **kwargs):
        print(f"[CALL-TIME] Before running '{func.__name__}'")
        result = func(*args, **kwargs)
        print(f"[CALL-TIME] After running '{func.__name__}'")
        return result
    return wrapper

@log_execution
def calculate_tax(amount: float) -> float:
    return amount * 0.2

# The line '@log_execution' executes IMMEDIATELY when the module is imported!
# It is 100% equivalent to:
# calculate_tax = log_execution(calculate_tax)

print("\n--- Invoking function now ---")
calculate_tax(100.0)
```

### Output:

```text
[IMPORT-TIME] Decorating function 'calculate_tax'

--- Invoking function now ---
[CALL-TIME] Before running 'calculate_tax'
[CALL-TIME] After running 'calculate_tax'
```

---

## 3. The Role of `@functools.wraps`

Without `@functools.wraps`, the decorated function loses its identity—its `__name__` becomes `"wrapper"` and its docstring is replaced. This breaks logging, debugging tracebacks, Sphinx docs, and **FastAPI route reflection**:

```python
import functools
import time

def timing_decorator(func):
    # Copies __name__, __doc__, __annotations__, and __module__ from func to wrapper
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        try:
            return func(*args, **kwargs)
        finally:
            print(f"Elapsed: {time.perf_counter() - start:.4f}s")
    return wrapper

@timing_decorator
def process_order(order_id: int):
    """Processes incoming shopping cart order."""
    return f"Order #{order_id} verified"

print("Name preserved:", process_order.__name__)  # Output: 'process_order'
print("Doc preserved:", process_order.__doc__)    # Output: 'Processes incoming shopping cart order.'
```

---

## 4. Parameterized Decorators (Decorator Factories)

When a decorator accepts parameters (like `@retry(max_attempts=3)`), you need **3 levels of nested functions**:

1. **Outer Factory:** Accepts decorator configuration arguments (`max_attempts`).
2. **Decorator:** Accepts the target function (`func`).
3. **Wrapper:** Accepts the runtime arguments (`*args, **kwargs`).

```python
import functools
import time

def retry(max_attempts: int = 3, delay: float = 0.5):
    """Decorator factory that retries flaky network/database calls."""
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            last_err = None
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as err:
                    last_err = err
                    print(f"Attempt {attempt}/{max_attempts} failed: {err}")
                    if attempt < max_attempts:
                        time.sleep(delay)
            raise RuntimeError(f"Operation failed after {max_attempts} retries") from last_err
        return wrapper
    return decorator

# Usage:
@retry(max_attempts=3, delay=0.1)
def fetch_vault_secret(secret_name: str) -> str:
    # Simulating intermittent network failure
    import random
    if random.random() < 0.5:
        raise ConnectionResetError("Connection lost to secret store")
    return "secret-token-value-xyz"
```

---

## 5. Async-Compatible Decorators

When wrapping asynchronous coroutines (`async def`), the wrapper must also be declared `async def` and awaited:

```python
import asyncio
import functools

def async_audit_log(func):
    @functools.wraps(func)
    async def wrapper(*args, **kwargs):
        print(f"[AUDIT] Starting async operation '{func.__name__}'")
        result = await func(*args, **kwargs)  # Crucial: Must await coroutine!
        print(f"[AUDIT] Completed async operation '{func.__name__}'")
        return result
    return wrapper

@async_audit_log
async def async_fetch_profile(user_id: int):
    await asyncio.sleep(0.01)
    return {"id": user_id, "username": "admin"}
```

---

## Next Steps

- [[Architecture/languages/python/13-context-managers-and-contextlib|13: Context Managers and contextlib]] — Resource cleanup protocols.
- [[Architecture/languages/python/15-asyncio-and-event-loop|15: Asyncio and the Event Loop]] — Event loop execution and coroutines.
