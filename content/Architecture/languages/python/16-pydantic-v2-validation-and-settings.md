---
title: "Pydantic v2 Validation and Settings"
description: "Master Pydantic v2: Rust-powered pydantic-core architecture, validator execution modes (before/after/wrap), strict vs lax coercion, discriminated unions, and pydantic-settings."
tags:
  - architecture
  - languages
  - python
  - pydantic
  - validation
date: 2026-10-19
aliases:
  - Architecture/languages/python/pydantic-v2-validation-and-settings
---

# Pydantic v2 Validation and Settings

**Pydantic v2** is the industry standard for schema validation and data serialization in Python. Rather than validating fields in slow Python loops, Pydantic v2 compiles your type annotations at class definition time into a native Rust schema tree executed by **`pydantic-core`**, delivering 5x–50x speed improvements.

---

## 1. Pydantic v2 Architecture: Rust-Backed Parsing

When you define a `BaseModel` class, Pydantic does not validate data in pure Python:

1. At module import time, Pydantic inspects type hints and constructs a Rust validator tree in memory.
2. At runtime, data validation executes inside compiled Rust C-extensions.
3. **Performance Tip:** Parsing JSON strings directly via `Model.model_validate_json(raw_bytes)` is up to **5x faster** than `Model.model_validate(json.loads(raw_str))` because JSON parsing and field validation happen in a single pass in Rust, skipping Python dictionary intermediate allocations!

---

## 2. Validator Execution Modes (`before`, `after`, `wrap`)

Pydantic v2 replaces legacy `@validator` and `@root_validator` with `@field_validator` and `@model_validator`. Choosing the correct execution mode is essential:

| Mode                         | Input Value Received                                              | When It Runs                                      | Best Used For                                                     |
| :--------------------------- | :---------------------------------------------------------------- | :------------------------------------------------ | :---------------------------------------------------------------- |
| **`mode="before"`**          | Raw, unparsed input (`Any`, e.g., string `"true"`, raw dict)      | Runs **before** Pydantic's internal type coercion | Sanitizing messy input, stripping strings, parsing custom formats |
| **`mode="after"`** (default) | Already-parsed, type-safe Python object (e.g., `int`, `datetime`) | Runs **after** Pydantic has coerced the type      | Business logic, range checks, comparing fields                    |
| **`mode="wrap"`**            | `(val, handler)`                                                  | Wraps around Pydantic's internal validator        | Error translation, fallback values, timing validation             |

### Field and Model Validator Walkthrough

```python
from pydantic import BaseModel, field_validator, model_validator

class UserAccount(BaseModel):
    username: str
    password: str
    confirm_password: str

    # 1. Field Validator: mode='before' sanitizes raw input before type parsing
    @field_validator("username", mode="before")
    @classmethod
    def sanitize_username(cls, raw_val: str) -> str:
        if not isinstance(raw_val, str):
            raise TypeError("Username must be a string")
        # Strip whitespace and convert to lowercase:
        return raw_val.strip().lower()

    # 2. Model Validator: mode='after' inspects the entire validated model
    @model_validator(mode="after")
    def verify_passwords_match(self) -> "UserAccount":
        if self.password != self.confirm_password:
            raise ValueError("Password confirmation does not match password!")
        return self

user = UserAccount(username="  AliceAdmin  ", password="secret123", confirm_password="secret123")
print("Sanitized username:", user.username)  # Output: 'aliceadmin'
```

---

## 3. Strict vs. Lax Coercion

By default, Pydantic operates in **Lax mode**, automatically coercing compatible types (e.g. `"42"` into `42`, or `1` into `True`). In financial or high-assurance APIs, enable **Strict mode** to reject coerced inputs:

```python
from pydantic import BaseModel, ConfigDict, StrictInt, ValidationError

class StrictPayment(BaseModel):
    model_config = ConfigDict(strict=True)  # Enforces strict mode across all fields

    amount_cents: StrictInt  # Rejects floats or string numbers

try:
    # Lax mode would accept "100" or 100.0; Strict mode immediately rejects it:
    payment = StrictPayment(amount_cents="100")
except ValidationError as err:
    print("Strict mode caught type error:\n", err.errors()[0]["msg"])
    # Output: Input should be a valid integer
```

---

## 4. Field Aliases and Serialization Control

Real-world APIs often receive `camelCase` keys from JavaScript frontends, while Python code conventions mandate `snake_case`.

```python
from pydantic import BaseModel, Field

class OrderPayload(BaseModel):
    # validation_alias: Name accepted during incoming input parsing
    # serialization_alias: Name emitted during model_dump() output
    order_id: str = Field(validation_alias="orderId", serialization_alias="orderId")
    total_amount: float = Field(validation_alias="totalAmount")

# Incoming payload uses camelCase:
incoming_json = {"orderId": "ord_9901", "totalAmount": 149.95}
order = OrderPayload.model_validate(incoming_json)

print("Python attribute (snake_case):", order.order_id)  # Output: ord_9901

# Serializing back to camelCase for frontend response:
print("Exported JSON with aliases:", order.model_dump_json(by_alias=True))
# Output: {"orderId":"ord_9901","totalAmount":149.95}
```

---

## 5. Discriminated Unions for Polymorphic JSON Payloads

When an API endpoint handles multiple event types (e.g., Stripe webhooks, Kubernetes events), a **Discriminated Union** uses a discriminator key (e.g., `"event_type"`) to jump directly to the correct model in $O(1)$ time:

```python
from typing import Annotated, Literal, Union
from pydantic import BaseModel, Field

class CardPayment(BaseModel):
    method: Literal["card"]
    last4: str
    card_brand: str

class BankTransfer(BaseModel):
    method: Literal["bank"]
    iban: str

# Discriminated union routed by 'method':
PaymentMethod = Annotated[
    Union[CardPayment, BankTransfer],
    Field(discriminator="method")
]

class CheckoutRequest(BaseModel):
    payment: PaymentMethod

# Pydantic reads 'method="card"' and instantly instantiates CardPayment:
checkout = CheckoutRequest.model_validate({
    "payment": {"method": "card", "last4": "4242", "card_brand": "visa"}
})

print("Validated payment type:", type(checkout.payment).__name__)  # Output: CardPayment
```

---

## 6. Application Configuration with `pydantic-settings`

Microservices follow the Twelve-Factor methodology: configuration is loaded from environment variables and `.env` files with automatic type conversion:

```python
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

class AppConfig(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,  # Reads PORT, port, or Port interchangeably
    )

    app_name: str = "order-service"
    port: int = Field(default=8080, validation_alias="PORT")
    database_url: str = Field(..., validation_alias="DATABASE_URL")  # Required!
    debug: bool = False

# Reading settings:
# Automatically pulls from os.environ, falling back to defaults or raising errors on missing keys
# config = AppConfig()
```

---

## Next Steps

- [[Architecture/languages/python/17-fastapi-foundations-and-dependency-injection|17: FastAPI Foundations and Dependency Injection]] — Integrating Pydantic with FastAPI routes.
- [[Architecture/languages/python/18-fastapi-production-middleware-async-db-and-auth|18: FastAPI Production: Lifespan and Async DB]] — Building production APIs.
