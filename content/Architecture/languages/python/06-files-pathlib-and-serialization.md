---
title: "Python Files, Pathlib, and Serialization"
description: "Master modern filesystem interaction with pathlib.Path, UTF-8 file I/O, streaming JSON serialization, CSV processing, and atomic writes via tempfile."
tags:
  - architecture
  - languages
  - python
  - io
date: 2026-10-19
aliases:
  - Architecture/languages/python/files-pathlib-and-serialization
---

# Python Files, Pathlib, and Serialization

Handling files, directories, and data formats requires avoiding platform-specific path bugs, managing file descriptors deterministically, and performing atomic writes to prevent data corruption.

---

## 1. Modern Path Handling with `pathlib.Path`

The `pathlib` module provides an object-oriented API that works seamlessly across Windows, macOS, and Linux, replacing legacy string-based functions from `os.path`:

```python
from pathlib import Path

# Constructing paths using the '/' operator:
config_dir = Path("/etc") / "cloudnative" / "services"
app_file = config_dir / "gateway.yaml"

print("Full path string:", app_file)
print("Filename (name):", app_file.name)            # Output: gateway.yaml
print("File stem without ext:", app_file.stem)      # Output: gateway
print("File extension (suffix):", app_file.suffix)  # Output: .yaml
print("Parent directory:", app_file.parent)         # Output: /etc/cloudnative/services

# Changing suffixes dynamically:
json_backup = app_file.with_suffix(".json")
print("Target backup path:", json_backup)           # Output: /etc/cloudnative/services/gateway.json

# Creating nested directories safely:
scratch_dir = Path("/tmp/app_runtime/cache")
scratch_dir.mkdir(parents=True, exist_ok=True)       # Creates parents if missing, no error if exists

# High-performance globbing:
current_logs = Path("/var/log").glob("*.log")        # Returns lazy iterator over matching paths
```

---

## 2. Robust File I/O and Streaming Line Readers

Always specify `encoding="utf-8"` explicitly. If omitted, Python defaults to the OS system locale (e.g. `cp1252` on Windows), which corrupts characters on cross-platform deployments:

```python
from pathlib import Path

log_path = Path("/tmp/metrics_stream.log")

# 1. Writing lines safely:
with log_path.open(mode="w", encoding="utf-8") as f:
    f.write("timestamp,metric,value\n")
    f.write("1713500000,cpu_load,0.78\n")
    f.write("1713500001,cpu_load,0.82\n")

# 2. Reading large files line-by-line (Memory Safe!):
# 'for line in f' streams lines lazily from the OS buffer without loading gigabyte files into RAM:
with log_path.open(mode="r", encoding="utf-8") as f:
    for line_num, line in enumerate(f, start=1):
        clean_line = line.strip()
        print(f"[{line_num:02d}] {clean_line}")
```

---

## 3. JSON Serialization: Custom Encoders and Decoders

Python's built-in `json` module supports both in-memory strings (`dumps`/`loads`) and direct disk streaming (`dump`/`load`):

```python
import json
from datetime import datetime, timezone
from decimal import Decimal

# Custom JSON encoder for domain types:
class CloudPayloadEncoder(json.JSONEncoder):
    def default(self, obj):
        # Convert Decimals to float or string
        if isinstance(obj, Decimal):
            return str(obj)
        # Convert datetime to ISO-8601 string
        if isinstance(obj, datetime):
            return obj.isoformat()
        # Fall back to default handler for standard types
        return super().default(obj)

payload = {
    "order_id": "ord_8821",
    "amount": Decimal("249.50"),
    "timestamp": datetime.now(timezone.utc),
    "features": ["canary", "auto-scale"],
}

# 1. Serialize in-memory to JSON string:
json_string = json.dumps(payload, cls=CloudPayloadEncoder, indent=2)
print("Serialized JSON:\n", json_string)

# 2. Parse JSON back into Python:
parsed_dict = json.loads(json_string)
print("Parsed Order ID:", parsed_dict["order_id"])
```

---

## 4. Atomic File Writes via `tempfile` and `os.replace`

If a server crashes while writing directly to `config.json`, the file will be left half-written and corrupted. The industry-standard pattern is to **write to a temporary file on the same filesystem and atomically rename it**:

```python
import os
import tempfile
from pathlib import Path

def atomic_write(target_path: Path, content: str):
    # Create temp file in the SAME directory as the target file
    # (guarantees they share the same physical filesystem partition!)
    parent_dir = target_path.parent
    parent_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile("w", dir=parent_dir, delete=False, encoding="utf-8") as tmp:
        tmp.write(content)
        tmp_name = tmp.name

    # Atomic rename using OS POSIX rename syscall
    # If the process or machine crashes, the original file is left completely untouched!
    os.replace(tmp_name, target_path)
    print(f"Atomically saved config to: {target_path}")

target = Path("/tmp/cloud_config/service.json")
atomic_write(target, '{"status": "production", "version": 2}')
```

---

## Next Steps

- [[Architecture/languages/python/07-modules-packages-and-uv|07: Modules, Packages, and uv]] — Virtualenvs, imports, and fast package management.
- [[Architecture/languages/python/16-pydantic-v2-validation-and-settings|16: Pydantic v2 Validation and Settings]] — Schema validation beyond standard JSON.
