---
title: "Python Functions, Arguments, and Scope"
description: "Master Python function definitions, the mutable default argument trap and func.__defaults__, *args and **kwargs, positional-only and keyword-only parameters, and LEGB scope."
tags:
  - architecture
  - languages
  - python
  - functions
date: 2026-10-19
aliases:
  - Architecture/languages/python/functions-arguments-and-scope
---

# Python Functions, Arguments, and Scope

Functions in Python are **first-class citizens**: they can be bound to names, stored inside collections, passed as arguments to other functions, and returned from functions.

---

## 1. Parameters vs. Arguments & Default Values

### The Mutable Default Argument Trap and `__defaults__`

In Python, default parameter expressions are evaluated **once at function definition time (when the module loads)**, not dynamically each time the function is called.

The default values are stored in the function object's internal attribute: `function.__defaults__`:

```python
# 💥 ANTI-PATTERN: Mutable list default
def append_event_bad(event: str, log: list = []):
    log.append(event)
    return log

# Call 1:
print(append_event_bad("login"))   # Output: ['login']
# Inspect function internals:
print("Internal defaults after call 1:", append_event_bad.__defaults__)
# Output: (['login'],)  <- The function object's default itself was mutated!

# Call 2:
print(append_event_bad("logout"))  # Output: ['login', 'logout'] -> Bug!

# -------------------------------------------------------------
# ✅ PRODUCTION PATTERN: Sentinel None Default
def append_event_clean(event: str, log: list | None = None):
    # If caller did not provide a list, create a brand-new list on THIS call
    if log is None:
        log = []
    log.append(event)
    return log

print(append_event_clean("login"))   # Output: ['login']
print(append_event_clean("logout"))  # Output: ['logout'] (fresh list instance)
```

---

## 2. Arbitrary Arguments: `*args` and `**kwargs`

- `*args` packs surplus positional arguments into an immutable `tuple`.
- `**kwargs` packs surplus keyword arguments into a mutable `dict`.

```python
def configure_service(name: str, *tags: str, **metadata):
    """
    - name: Required positional/keyword parameter
    - tags: Packed into tuple
    - metadata: Packed into dict
    """
    print(f"Service Name: {name}")
    print(f"Tags tuple ({type(tags).__name__}): {tags}")
    print(f"Metadata dict ({type(metadata).__name__}): {metadata}")

# Invocation:
configure_service("payment-api", "v2", "eu-west-1", timeout=5.0, debug=True)
# Output:
# Service Name: payment-api
# Tags tuple (tuple): ('v2', 'eu-west-1')
# Metadata dict (dict): {'timeout': 5.0, 'debug': True}

# Unpacking arguments at invocation time:
# Use '*' to unpack an iterable into positional arguments
# Use '**' to unpack a dictionary into keyword arguments
runtime_options = {"timeout": 10.0, "debug": False}
category_tags = ["prod", "tier-1"]

configure_service("billing-worker", *category_tags, **runtime_options)
```

---

## 3. Positional-Only and Keyword-Only Parameters

Introduced in PEP 570 and PEP 3102, Python allows you to enforce strict API call signatures using `/` and `*`:

```python
# Signature Anatomy:
# def func(pos_only1, pos_only2, /, standard, *, kw_only1, kw_only2):
#         [--------------------]     [------]     [-----------------]
#            Positional-Only         Standard       Keyword-Only

def query_database(
    query: str,                # Positional-only (left of /)
    /,
    timeout: float = 30.0,     # Standard: positional or keyword
    *,
    strict: bool = False,      # Keyword-only (right of *)
    pool_name: str = "main"    # Keyword-only
):
    print(f"SQL: {query} | Timeout: {timeout}s | Strict: {strict} | Pool: {pool_name}")

# Valid Invocations:
query_database("SELECT 1", 5.0, strict=True, pool_name="replica")
query_database("SELECT * FROM users", timeout=10.0, strict=False)

# Invalid Invocations (Raise TypeError at runtime):
# 1. Passing positional-only param as keyword:
# query_database(query="SELECT 1")
# -> TypeError: query_database() got some positional-only arguments passed as keyword arguments: 'query'

# 2. Passing keyword-only param positionally:
# query_database("SELECT 1", 5.0, True)
# -> TypeError: query_database() takes from 1 to 2 positional arguments but 3 were given
```

> [!TIP]
> Always use `*` to force keyword-only arguments for boolean flags (`strict=True`, `dry_run=True`). It prevents cryptic call sites like `create_user("Alice", True, False, True)`.

---

## 4. The LEGB Scoping Rules and `nonlocal` / `global`

When resolving variable names, Python looks through 4 scopes in order (**LEGB**):

1. **L**ocal: Defined inside the current function body.
2. **E**nclosing: Defined in outer nested functions (closures).
3. **G**lobal: Defined at the top-level module scope.
4. **B**uilt-in: Provided by Python runtime (`len`, `range`, `ValueError`).

```python
# Global Scope
service_status = "READY"

def outer_service():
    # Enclosing Scope
    request_counter = 0

    def inner_handler():
        # Local Scope
        # 'nonlocal' allows rebinding the variable in the enclosing outer_service scope
        nonlocal request_counter
        request_counter += 1

        # Reading global variable without rebinding works without 'global' keyword
        print(f"[{service_status}] Handled request #{request_counter}")
        return request_counter

    return inner_handler

handler = outer_service()
handler()  # Output: [READY] Handled request #1
handler()  # Output: [READY] Handled request #2
```

---

## 5. Lambda Functions and Higher-Order Callables

A `lambda` is an anonymous, inline function containing a single expression. It implicitly returns the result of that expression:

```python
services = [
    {"name": "auth-service", "latency_ms": 12.4, "replicas": 3},
    {"name": "payment-api",  "latency_ms": 45.1, "replicas": 5},
    {"name": "order-worker", "latency_ms": 5.8,  "replicas": 2},
]

# Sort services by latency ascending:
by_latency = sorted(services, key=lambda s: s["latency_ms"])
print("Fastest service:", by_latency[0]["name"])  # Output: order-worker

# Sort services by replicas descending:
by_replicas = sorted(services, key=lambda s: s["replicas"], reverse=True)
print("Largest pool:", by_replicas[0]["name"])   # Output: payment-api
```

---

## Next Steps

- [[Architecture/languages/python/03-lists-tuples-sets-and-dicts|03: Lists, Tuples, Sets, and Dictionaries]] — Core data structure complexity and operations.
- [[Architecture/languages/python/12-closures-and-decorators|12: Closures and Decorators]] — Advanced metaprogramming and decorator factories.
