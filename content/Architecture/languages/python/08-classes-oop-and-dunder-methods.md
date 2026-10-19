---
title: "Python Classes, OOP, and Dunder Methods"
description: "Master object-oriented architecture in Python: self binding mechanics, instance vs class vs static methods, @property encapsulation, the hash contract, and core dunder protocols."
tags:
  - architecture
  - languages
  - python
  - oop
date: 2026-10-19
aliases:
  - Architecture/languages/python/classes-oop-and-dunder-methods
---

# Python Classes, OOP, and Dunder Methods

Python uses a dynamic, class-based object model where classes themselves are first-class runtime objects (instances of `type`). To design maintainable object-oriented architectures, you must understand how method binding works and how Python's **Data Model (Dunder Protocols)** integrates custom classes into the language's native syntax.

---

## 1. How Method Binding and `self` Actually Work

In many languages, `this` is a magic keyword automatically injected into methods. In Python, **`self` is explicit**.

When you define a method on a class, it is a regular function stored in the class's dictionary. When accessed through an instance, Python's descriptor protocol wraps the function into a **bound method**, automatically passing the instance as the first argument:

```python
class DatabasePool:
    def __init__(self, dsn: str):
        self.dsn = dsn

    def query(self, sql: str) -> str:
        return f"Executing '{sql}' on {self.dsn}"

pool = DatabasePool("postgres://localhost:5432/main")

# Calling via instance syntax:
res1 = pool.query("SELECT 1")

# Is 100% equivalent to calling the class function directly and passing the instance:
res2 = DatabasePool.query(pool, "SELECT 1")

print("Are both invocation results identical?", res1 == res2)  # Output: True
```

---

## 2. Instance, Class, and Static Methods

Choosing between instance, class, and static methods reflects the scope of state being manipulated:

```python
class ConnectionManager:
    # Class variable: shared across all instances
    default_timeout: float = 30.0
    active_instances: int = 0

    def __init__(self, host: str, port: int):
        # Instance variables: private to each object
        self.host = host
        self.port = port
        ConnectionManager.active_instances += 1

    # 1. Instance Method: Accesses and mutates specific instance state via 'self'
    def connect(self) -> str:
        return f"Connected to {self.host}:{self.port}"

    # 2. Class Method: Receives the class 'cls' instead of an instance.
    # Idiomatic Pattern: Alternative Constructors / Factory Methods
    @classmethod
    def from_url(cls, url: str) -> "ConnectionManager":
        # e.g., parses 'redis://10.0.0.1:6379'
        clean_url = url.removeprefix("redis://")
        host_str, port_str = clean_url.split(":", 1)
        # Returns a fresh instance of whichever class was called (subclass-safe!)
        return cls(host=host_str, port=int(port_str))

    # 3. Static Method: Does not receive 'self' or 'cls'.
    # Pure utility function scoped under the class namespace for logical grouping.
    @staticmethod
    def is_valid_port(port: int) -> bool:
        return 1 <= port <= 65535

# Usage Demonstration:
manager = ConnectionManager.from_url("redis://10.0.0.5:6379")
print(manager.connect())  # Output: Connected to 10.0.0.5:6379
print("Port valid?", ConnectionManager.is_valid_port(6379))  # Output: True
```

---

## 3. Encapsulation with `@property`

Python does not use `private` keywords. It uses naming conventions (`_protected` with a single underscore, or `__mangled` with two underscores) combined with `@property` to create managed attributes:

```python
class CloudServiceQuota:
    def __init__(self, service_name: str, max_replicas: int):
        self.service_name = service_name
        self._max_replicas = max_replicas  # Protected attribute

    # Getter: Accessed like an attribute 'quota.max_replicas'
    @property
    def max_replicas(self) -> int:
        return self._max_replicas

    # Setter: Validates values upon assignment 'quota.max_replicas = 10'
    @max_replicas.setter
    def max_replicas(self, value: int):
        if not isinstance(value, int) or value < 1:
            raise ValueError(f"Replicas must be an integer >= 1, got {value}")
        if value > 100:
            raise ValueError("Exceeds maximum organizational quota limit of 100")
        self._max_replicas = value

quota = CloudServiceQuota("auth-api", 5)
quota.max_replicas = 12  # Runs setter validation
print("Updated replicas:", quota.max_replicas)

try:
    quota.max_replicas = -3  # Raises ValueError!
except ValueError as err:
    print("Caught validation rejection:", err)
```

---

## 4. The Python Data Model & Essential Dunder Protocols

Special methods surrounded by double underscores ("dunder" methods) let your classes hook into Python's native syntax (`str()`, `==`, `len()`, `in`, `obj()`).

### The Reference Table of Core Dunder Protocols

| Protocol                  | Dunder Methods           | Syntax Trigger                              | Purpose                                                     |
| :------------------------ | :----------------------- | :------------------------------------------ | :---------------------------------------------------------- |
| **String Representation** | `__repr__`, `__str__`    | `repr(x)`, `f"{x!r}"`, `str(x)`, `print(x)` | Unambiguous debugging representation vs user-facing display |
| **Equality & Hashing**    | `__eq__`, `__hash__`     | `a == b`, `hash(x)`, `dict[x]`, `x in set`  | Value comparison and hash table key eligibility             |
| **Sequence Emulation**    | `__len__`, `__getitem__` | `len(x)`, `x[i]`, `for item in x:`          | Array/container indexing, slicing, and iteration            |
| **Callable Objects**      | `__call__`               | `x(*args, **kwargs)`                        | Allows an instance to be invoked like a function            |
| **Truthiness**            | `__bool__`               | `bool(x)`, `if x:`                          | Custom truth value evaluation (defaults to `__len__ > 0`)   |

---

## 5. The Hash Contract: `__eq__` and `__hash__`

A critical architectural concept in Python:

1. By default, every custom class inherits `__eq__` (which compares object identity `is`) and `__hash__` (which uses `id(self)`).
2. **If you override `__eq__`, Python automatically sets `__hash__ = None`!** This makes instances unhashable, meaning they cannot be placed into a `set` or used as `dict` keys.
3. Why? If two objects are equal (`a == b`), they **MUST produce identical hash values** (`hash(a) == hash(b)`). Furthermore, if an object's hash changes after being stored in a dictionary, the dictionary's hash buckets become corrupted!

```python
# Implementing an Immutable, Hashable Domain Value Object:
class RouteKey:
    def __init__(self, method: str, path: str):
        # Store attributes as private/read-only
        self._method = method.upper()
        self._path = path

    @property
    def method(self) -> str:
        return self._method

    @property
    def path(self) -> str:
        return self._path

    # Step 1: Define equality
    def __eq__(self, other: object) -> bool:
        if not isinstance(other, RouteKey):
            return False
        return self._method == other._method and self._path == other._path

    # Step 2: Define hash based on the EXACT same immutable fields compared in __eq__
    def __hash__(self) -> int:
        return hash((self._method, self._path))

    def __repr__(self) -> str:
        return f"RouteKey({self._method!r}, {self._path!r})"

# Hash table usage:
routing_table = {}
key1 = RouteKey("GET", "/api/v1/health")
key2 = RouteKey("GET", "/api/v1/health")

routing_table[key1] = "health_check_handler"

# Lookup works using key2 because key1 == key2 AND hash(key1) == hash(key2):
print("Handler lookup:", routing_table[key2])  # Output: 'health_check_handler'
```

---

## 6. Callable Instances with `__call__`

Implementing `__call__` turns an instance into a callable object that maintains state between invocations:

```python
class SlidingWindowCounter:
    def __init__(self, threshold: int):
        self.threshold = threshold
        self.total_requests = 0

    def __call__(self, client_ip: str) -> bool:
        self.total_requests += 1
        if self.total_requests > self.threshold:
            print(f"[REJECT] IP {client_ip} exceeded threshold ({self.threshold})")
            return False
        print(f"[ACCEPT] IP {client_ip} request #{self.total_requests}")
        return True

# Counter instance behaves like a function, but encapsulates persistent state:
is_allowed = SlidingWindowCounter(threshold=2)
is_allowed("10.0.0.1")  # Output: [ACCEPT] IP 10.0.0.1 request #1
is_allowed("10.0.0.1")  # Output: [ACCEPT] IP 10.0.0.1 request #2
is_allowed("10.0.0.1")  # Output: [REJECT] IP 10.0.0.1 exceeded threshold (2)
```

---

## Next Steps

- [[Architecture/languages/python/09-inheritance-composition-and-dataclasses|09: Inheritance, Composition, and Dataclasses]] — The Diamond Problem, MRO, and modern dataclasses.
- [[Architecture/languages/python/20-descriptors-metaclasses-and-metaprogramming|20: Descriptors, Metaclasses, and Metaprogramming]] — Deep dive into attribute resolution and descriptors.
