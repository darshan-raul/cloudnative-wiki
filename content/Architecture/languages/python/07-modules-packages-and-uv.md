---
title: "Python Modules, Packages, and uv"
description: "Master Python's import system, sys.modules caching, circular import solutions with TYPE_CHECKING, virtual environment anatomy, and lightning-fast package management with Astral uv."
tags:
  - architecture
  - languages
  - python
  - tooling
date: 2026-10-19
aliases:
  - Architecture/languages/python/modules-packages-and-uv
---

# Python Modules, Packages, and uv

Structuring large Python codebases requires understanding how Python's import system resolves names, how `sys.modules` caches loaded files, and how modern tooling like Astral's `uv` handles dependency management.

---

## 1. How Python Finds and Caches Modules (`sys.path` & `sys.modules`)

When you write `import my_module`, Python executes a two-step process:

1. **Cache Inspection:** It checks the `sys.modules` dictionary. If `my_module` is already loaded, it immediately returns the cached module object without re-executing the file.
2. **Path Search:** If not cached, it searches the directories listed in `sys.path` in order:
   - The directory of the entrypoint script being executed.
   - The `PYTHONPATH` environment variable directories.
   - The standard library directories.
   - The virtual environment's `site-packages` directory.

```python
import sys

# 1. Inspect loaded modules in memory:
print("Is 'sys' already cached?", "sys" in sys.modules)  # Output: True

# 2. Inspect module search order:
print("\nFirst 3 search paths in sys.path:")
for idx, p in enumerate(sys.path[:3], start=1):
    print(f"[{idx}] {p}")
```

---

## 2. Circular Import Traps and the `TYPE_CHECKING` Pattern

A circular import happens when Module A imports Module B, but Module B imports Module A before Module A has finished executing its top-level statements.

```python
# 💥 THE TRAP:
# user_service.py: from order_service import Order
# order_service.py: from user_service import User
# -> Raises ImportError: cannot import name 'User' from partially initialized module!

# ✅ SOLUTION: The TYPE_CHECKING Guard
# In order_service.py:
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    # This block executes ONLY during static type checking (mypy/pyright),
    # NEVER during runtime! Circular import is completely avoided!
    from user_service import User

class Order:
    def __init__(self, owner: "User"):
        self.owner = owner
```

---

## 3. Package Layout and Explicit Exports (`__all__`)

Recommended cloud-native service repository layout:

```
payment_service/
├── pyproject.toml              # Project dependencies and build metadata
├── uv.lock                     # Deterministic cryptographic lockfile
├── src/
│   └── payment_service/
│       ├── __init__.py         # Defines the public API via __all__
│       ├── config.py           # Pydantic Settings
│       ├── api/
│       │   ├── __init__.py
│       │   └── routes.py       # FastAPI APIRouter
│       └── core/
│           ├── __init__.py
│           └── processor.py
└── tests/
    ├── conftest.py
    └── test_api.py
```

In `src/payment_service/__init__.py`:

```python
# Expose only explicit public symbols to external callers:
from payment_service.config import AppSettings
from payment_service.core.processor import process_payment

# If a user runs 'from payment_service import *', only these 2 symbols are exported:
__all__ = ["AppSettings", "process_payment"]
```

---

## 4. Modern Dependency Management with Astral's `uv`

Astral's **`uv`** is written in Rust and is 10x–100x faster than legacy `pip`, `poetry`, and `pipenv`. It handles Python versions, virtual environments, lockfiles, and script execution in a single binary.

### Essential `uv` Workflows

```bash
# 1. Initialize a new project with pyproject.toml
uv init payment-service
cd payment-service

# 2. Pin and install a specific Python runtime version (no pyenv needed!)
uv python install 3.12
uv venv --python 3.12

# 3. Add production dependencies (auto-resolves uv.lock and updates pyproject.toml)
uv add fastapi "pydantic>=2.7.0" uvicorn

# 4. Add development-only dependencies
uv add --dev pytest ruff mypy

# 5. Run commands directly inside the project virtualenv without manual 'source activate':
uv run python -m payment_service
uv run pytest
```

### Standard `pyproject.toml` (PEP 621)

```toml
[project]
name = "payment-service"
version = "0.1.0"
description = "Cloud-native payment service"
readme = "README.md"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.111.0",
    "pydantic>=2.7.0",
    "uvicorn>=0.30.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.2.0",
    "ruff>=0.4.0",
    "mypy>=1.10.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

---

## Next Steps

- [[Architecture/languages/python/08-classes-oop-and-dunder-methods|08: Classes, OOP, and Dunder Methods]] — Object-oriented architecture and magic methods.
- [[Architecture/languages/python/24-production-packaging-docker-and-deployment|24: Production Packaging, Docker, and Deployment]] — Multi-stage Docker builds using `uv`.
