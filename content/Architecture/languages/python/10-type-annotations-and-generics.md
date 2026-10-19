---
title: "Python Type Annotations and Generics"
description: "Master modern Python static typing: Nominal vs Structural subtyping (Protocol), Python 3.12+ generics [T], Variance (Covariance vs Invariance), and Annotated metadata."
tags:
  - architecture
  - languages
  - python
  - typing
date: 2026-10-19
aliases:
  - Architecture/languages/python/type-annotations-and-generics
---

# Python Type Annotations and Generics

Python remains dynamically typed at runtime, but type annotations (PEP 484, 526, 695) enable powerful compile-time verification via `mypy` and `pyright`. They eliminate entire categories of production bugs (`AttributeError`, `TypeError`, `NoneType has no attribute 'x'`).

---

## 1. Nominal vs. Structural Subtyping (`Protocol`)

Python provides two paradigms for polymorphism:

| Paradigm                 | Implemented Via   | How It Works                                                                             | Best Suited For                                      |
| :----------------------- | :---------------- | :--------------------------------------------------------------------------------------- | :--------------------------------------------------- |
| **Nominal Subtyping**    | `abc.ABC`         | Subclass **must explicitly inherit** from the base class (`class S3(StorageBackend):`)   | Strict internal hierarchies within your own codebase |
| **Structural Subtyping** | `typing.Protocol` | Subclass satisfies the interface **implicitly** by having matching methods (Duck Typing) | Third-party libraries, test mocks, and decoupling    |

### Duck Typing with Static Checking: `typing.Protocol`

```python
from typing import Protocol

# Define the expected interface contract
class HealthCheckable(Protocol):
    def check_health(self) -> bool:
        """Returns True if the component is operational."""
        ...

# Two completely unrelated classes that DO NOT inherit from HealthCheckable:
class DatabaseCluster:
    def check_health(self) -> bool:
        return True

class RedisCache:
    def check_health(self) -> bool:
        return False

# Function accepting ANY object that quacks like a HealthCheckable:
def verify_system_readiness(components: list[HealthCheckable]) -> bool:
    for c in components:
        if not c.check_health():
            return False
    return True

# Validated cleanly by mypy/pyright without any subclassing boilerplate!
print("System ready?", verify_system_readiness([DatabaseCluster(), RedisCache()]))
# Output: System ready? False
```

---

## 2. Generics with Python 3.12+ `[T]` Syntax

Python 3.12 (PEP 695) replaced cumbersome `TypeVar` declarations with clean generic syntax:

```python
# 1. Generic Function: Preserves the exact element type between input and output
def first_element[T](items: list[T]) -> T | None:
    return items[0] if items else None

num = first_element([10, 20, 30])    # mypy infers 'num' as int
text = first_element(["a", "b"])     # mypy infers 'text' as str

# 2. Generic Class: Reusable thread-safe container
class ThreadSafeBox[T]:
    def __init__(self, value: T):
        self._value = value

    def get(self) -> T:
        return self._value

    def set(self, new_val: T) -> None:
        self._value = new_val

int_box = ThreadSafeBox[int](42)
str_box = ThreadSafeBox[str]("token_secret")

# 3. Modern Type Statement (PEP 695):
type JSONValue = str | int | float | bool | None | dict[str, "JSONValue"] | list["JSONValue"]
type Coordinates = tuple[float, float]
```

---

## 3. Understanding Variance: Invariant vs. Covariant Collections

A classic typing pitfall in Python:

> **Question:** If `Dog` is a subclass of `Animal`, is `list[Dog]` a subclass of `list[Animal]`?  
> **Answer: NO!** In Python, `list` is **Invariant**.

### Why `list[Dog]` Cannot Be Passed as `list[Animal]`:

```python
class Animal: pass
class Dog(Animal): pass
class Cat(Animal): pass

def poison_kennel(animals: list[Animal]):
    # If list[Dog] were accepted as list[Animal], this legal line would inject a Cat into a Dog list!
    animals.append(Cat())

dogs: list[Dog] = [Dog(), Dog()]
# poison_kennel(dogs)
# mypy ERROR: Argument 1 to "poison_kennel" has incompatible type "list[Dog]"; expected "list[Animal]"
```

### The Solution: Use Covariant Read-Only Sequences (`Sequence[T]`)

If a function **only reads** from the collection, use `collections.abc.Sequence` (which is **covariant**):

```python
from collections.abc import Sequence

def count_animals(animals: Sequence[Animal]) -> int:
    # Safe! We only read elements; we cannot mutate or append to a Sequence
    return len(animals)

dogs: list[Dog] = [Dog(), Dog()]
print("Counted:", count_animals(dogs))  # Passes mypy cleanly!
```

---

## 4. `Annotated` (Metadata Attachments)

`Annotated[T, ...]` (PEP 593) attaches runtime metadata to type hints without modifying static type checking. This is the foundational mechanism powering **FastAPI dependency injection** and **Pydantic validation**:

```python
from typing import Annotated, get_type_hints

# Attach custom metadata to an integer type
PortNumber = Annotated[int, "Network TCP Port (1-65535)", {"min": 1, "max": 65535}]

class ServerConfig:
    port: PortNumber = 8080

# How frameworks like FastAPI or Pydantic inspect metadata at runtime:
hints = get_type_hints(ServerConfig, include_extras=True)
port_annotation = hints["port"]

print("Raw type:", port_annotation.__origin__)       # <class 'int'>
print("Attached metadata:", port_annotation.__metadata__)
# Output: ('Network TCP Port (1-65535)', {'min': 1, 'max': 65535})
```

---

## Next Steps

- [[Architecture/languages/python/11-iterators-generators-and-itertools|11: Iterators, Generators, and Itertools]] — Lazy evaluation pipelines.
- [[Architecture/languages/python/16-pydantic-v2-validation-and-settings|16: Pydantic v2 Validation and Settings]] — Leveraging types for runtime validation.
