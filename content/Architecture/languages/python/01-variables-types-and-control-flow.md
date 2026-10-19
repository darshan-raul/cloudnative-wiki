---
title: "Python Variables, Types, and Control Flow"
description: "Master Python's dynamic object reference model, small-integer caching, primitive data types, truthiness evaluation, f-strings, control flow, and structural pattern matching."
tags:
  - architecture
  - languages
  - python
  - basics
date: 2026-10-19
aliases:
  - Architecture/languages/python/variables-types-and-control-flow
---

# Python Variables, Types, and Control Flow

To write robust Python, you must first unlearn a common mental model from languages like C, C++, or Go. In those languages, a variable is a named memory box that holds raw bits. In Python, **variables are merely named pointers (references)** bound to dynamically allocated objects in heap memory.

---

## 1. Object References and Dynamic Typing

When you write `x = 42`, Python does not store the number 42 inside `x`. Instead, it allocates an integer object representing `42` in heap memory, and binds the name `x` to that object's memory address.

```python
# Multiple variable names can bind to the exact same heap object
a = [1, 2, 3]
b = a  # 'b' now points to the exact same list address in memory

b.append(4)  # Mutating through 'b' affects 'a' directly!

print("List a:", a)  # Output: [1, 2, 3, 4]
print("List b:", b)  # Output: [1, 2, 3, 4]

# Identity vs Equality:
# 'is' checks if both names share the identical memory address (id(a) == id(b))
# '==' checks if the objects have equivalent values (__eq__)
print("Is a the exact same object as b?", a is b)  # Output: True (identity match)
print("Do a and b have equal contents?", a == b)  # Output: True (value equality)

# Rebinding a name creates a completely new object in memory:
b = [1, 2, 3, 4]  # Allocates a fresh list with its own unique memory address
print("Is a the same object after rebinding?", a is b)  # Output: False (different id!)
print("Do a and b still have equal contents?", a == b)  # Output: True
```

### The CPython Small-Integer Caching Optimization

As a memory and CPU optimization, CPython pre-allocates and caches small integers in the range **`-5` to `256`** at interpreter startup. When you reference any integer within this range, Python reuses the existing cached object:

```python
# Caching in action:
x = 256
y = 256
print("x is y (within cached range -5..256):", x is y)  # Output: True (same cached object!)

# Outside the cached range:
x = 1000
y = 1000
print("x is y (outside cached range):", x is y)  # Output: False (two separate heap allocations)
print("x == y (values still match):", x == y)  # Output: True
```

> [!WARNING]
> Never use `is` to compare values or numbers! Always use `==` for values. Reserve `is` strictly for checking singletons like `if x is None:` or `if x is True:`.

---

## 2. Primitive Data Types and Numbers

Python features arbitrary-precision integers (they never overflow 64-bit boundaries), IEEE 754 floating-point numbers, booleans, and complex numbers.

```python
# 1. Arbitrary-Precision Integers:
# Python integers automatically allocate more memory as needed. They never overflow!
huge_num = 2**100
print("Huge integer:", huge_num)
# Output: 1267650600228229401496703205376

# 2. Floating-Point Precision Trap (IEEE 754):
# Binary floats cannot represent certain base-10 fractions exactly
f1 = 0.1 + 0.2
print("0.1 + 0.2 in binary float:", f1)  # Output: 0.30000000000000004
print("Does 0.1 + 0.2 == 0.3?", f1 == 0.3)  # Output: False!

# 3. Financial & High-Precision Calculations (decimal module):
# Use Decimal when rounding errors cannot be tolerated (billing, ledgers, currencies)
from decimal import Decimal

d1 = Decimal("0.1") + Decimal("0.2")
print("Decimal sum:", d1)  # Output: 0.3
print("Does Decimal sum == Decimal('0.3')?", d1 == Decimal("0.3"))  # Output: True
```

---

## 3. Truthiness and Logical Operations

Every Python object has an intrinsic boolean evaluation (`bool(x)`):

- **Falsy values:** `None`, `False`, numeric zeros (`0`, `0.0`, `Decimal(0)`), empty sequences (`""`, `()`, `[]`), and empty mappings (`{}`, `set()`).
- **Truthy values:** Any non-zero number, non-empty string, collection, or object instance.

```python
def process_queue(items=None):
    # Idiomatic Pythonic check: catches both items=None and items=[] in one check
    if not items:
        print("Queue is empty or uninitialized, skipping processing.")
        return

    print(f"Processing {len(items)} items from queue...")

process_queue(None)  # Output: Queue is empty or uninitialized...
process_queue([])  # Output: Queue is empty or uninitialized...
process_queue(["job-1", "job-2"])  # Output: Processing 2 items from queue...
```

### Short-Circuit Return Values

Python's `or` and `and` operators do not just return `True` or `False`; they return the **actual operand** that determined the outcome:

```python
# 'or' returns the first truthy value, or the last falsy value if all are falsy
default_host = "127.0.0.1"
user_input = ""  # Falsy empty string
host = user_input or default_host
print("Resolved host:", host)  # Output: '127.0.0.1'

# 'and' returns the first falsy value, or the last truthy value if all are truthy
auth_token = "valid_token_xyz"
has_permission = True
can_access = auth_token and has_permission
print("Access granted:", can_access)  # Output: True
```

---

## 4. Modern String Formatting (F-Strings)

Introduced in Python 3.6 and enhanced in 3.12+, f-strings are evaluated at runtime directly in C bytecode, making them faster and more readable than `%` formatting or `str.format()`:

```python
service = "payment-gateway"
latency_ms = 45.6789
requests_count = 1250000
status_code = 200

# Rich format specifiers:
# :, -> comma thousands separator
# .2f -> round to 2 decimal places
# #06d -> zero pad integer to 6 digits
print(f"Service: {service.upper()}")
print(f"Total Requests: {requests_count:,}")  # Output: 1,250,000
print(f"Latency: {latency_ms:.2f}ms")  # Output: 45.68ms
print(f"Formatted Status: {status_code:#06d}")  # Output: 000200

# Self-documenting debugging with '=' (Python 3.8+):
cpu_load = 78.4
print(f"{cpu_load=}")  # Output: cpu_load=78.4
```

---

## 5. Control Flow: Loops and the `for...else` Construct

Python's `for` loop iterates over any iterable container. A uniquely Pythonic construct is the **`for...else`** block:

The `else:` block attached to a loop executes **only if the loop completed naturally without encountering a `break`**:

```python
target_id = 42
records = [10, 25, 33, 42, 99]

for record in records:
    if record == target_id:
        print(f"Match found: {record}")
        break  # Loop terminates early; the 'else' block will NOT run!
else:
    # Runs only if the loop exhausted all elements without hitting 'break'
    print("Record not found in the dataset.")

# Practical search pattern without extra 'found = False' boolean flags:
blocked_ips = ["192.168.1.5", "10.0.0.99"]
incoming_ip = "172.16.0.4"

for blocked in blocked_ips:
    if incoming_ip == blocked:
        print("Access denied: IP is blacklisted!")
        break
else:
    print(f"Access granted for IP: {incoming_ip}")
```

---

## 6. Structural Pattern Matching (`match / case`)

Introduced in Python 3.10 (PEP 634), `match/case` is not merely an alternative to `switch/case`. It deconstructs complex nested objects, types, mappings, and sequences, and can bind variables and apply runtime guards:

```python
def route_event(event: dict):
    match event:
        # 1. Matches dict with specific keys, types, and an 'if' guard
        case {"type": "deploy", "service": str(svc), "replicas": int(r)} if r > 0:
            print(f"[DEPLOY] Starting {svc} with {r} replicas")

        # 2. Matches zero replica case
        case {"type": "deploy", "service": str(svc), "replicas": 0}:
            print(f"[SCALE-DOWN] Hibernating service {svc} to 0 replicas")

        # 3. Unpacks remaining dictionary keys into '**extra'
        case {"type": "rollback", "service": str(svc), **extra}:
            print(f"[ROLLBACK] Rolling back {svc}. Extra flags: {extra}")

        # 4. Sequence pattern matching: matches a list with at least 2 items
        case ["alert", severity, *messages]:
            print(f"[ALERT] {severity.upper()} -> {' '.join(messages)}")

        # 5. Wildcard catch-all pattern
        case _:
            print(f"[REJECTED] Unknown payload structure: {event}")


# Test cases demonstrating pattern matching in action:
route_event({"type": "deploy", "service": "auth-api", "replicas": 3})
route_event({"type": "deploy", "service": "payment-api", "replicas": 0})
route_event({"type": "rollback", "service": "orders", "target_tag": "v1.4.2"})
route_event(["alert", "critical", "database", "disk", "full"])
route_event({"unexpected": "data"})
```

---

## Next Steps

- [[Architecture/languages/python/02-functions-arguments-and-scope|02: Functions, Arguments, and Scope]] — Parameter semantics, `*args`, `**kwargs`, and closure scoping.
- [[Architecture/languages/python/03-lists-tuples-sets-and-dicts|03: Lists, Tuples, Sets, and Dictionaries]] — Core data structures and hash map mechanics.
