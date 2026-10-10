---
title: Test Doubles — Dummies, Stubs, Mocks, Fakes & Spies
description: Gerard Meszaros' taxonomy of Test Doubles — definitions, comparative differences, and implementation examples of Mocks, Stubs, Fakes, and Spies
tags:
  - testing
  - unit-testing
  - mocks
  - stubs
  - fakes
date: 2026-10-10
---

# Test Doubles — Dummies, Stubs, Mocks, Fakes & Spies

A **Test Double** (a term coined by Gerard Meszaros) is any object that stands in for a real production component during automated testing, analogous to a stunt double in a film.

Developers frequently misuse the word "mock" to describe all test doubles. Understanding the exact taxonomy prevents fragile, over-specified tests.

---

## 1. The 5 Types of Test Doubles

```
┌────────────────────────────────────────────────────────┐
│                      Test Double                       │
├──────────┬──────────┬──────────┬───────────┬───────────┤
│  Dummy   │   Stub   │   Spy    │   Mock    │   Fake    │
└──────────┴──────────┴──────────┴───────────┴───────────┘
```

| Type      | Definition                                                                                | State vs Behavior         | Example                                                           |
| :-------- | :---------------------------------------------------------------------------------------- | :------------------------ | :---------------------------------------------------------------- |
| **Dummy** | Passed into methods to satisfy parameter signatures, but **never actually used**.         | None                      | `None`, empty string, empty struct                                |
| **Stub**  | Provides **canned answers** to calls made during the test.                                | State Verification        | Returns `{"rate": 1.25}` whenever `get_exchange_rate()` is called |
| **Spy**   | A stub that also **records telemetry** (invocation count, arguments passed).              | State Verification        | Verifies `audit_log.record()` was called with `user_id=10`        |
| **Mock**  | Pre-programmed with **strict behavioral expectations**; fails if unexpected calls occur.  | **Behavior Verification** | `mock.expects(1).call("send_sms").with("555-0199")`               |
| **Fake**  | Has a **working business implementation**, but takes shortcuts unsuitable for production. | State Verification        | In-memory SQLite DB, Fake Stripe Gateway                          |

---

## 2. In-Depth Examples (Python)

### 1. The Stub (Canned Answers)

```python
class StubPaymentGateway:
    def charge(self, amount: float) -> bool:
        return True # Always succeeds for testing positive checkout flow
```

### 2. The Spy (Recording Invocations)

```python
class SpyEmailSender:
    def __init__(self):
        self.sent_messages = []

    def send_email(self, to: str, subject: str):
        self.sent_messages.append({"to": to, "subject": subject})

# In test:
assert len(spy_mailer.sent_messages) == 1
assert spy_mailer.sent_messages[0]["to"] == "alice@example.com"
```

### 3. The Fake (Working In-Memory Implementation)

```python
class FakeUserRepository:
    def __init__(self):
        self._users = {} # In-memory dictionary replaces PostgreSQL

    def save(self, user):
        self._users[user.id] = user

    def find_by_id(self, user_id):
        return self._users.get(user_id)
```

---

## 3. Mocking Best Practices: State vs Behavior Verification

- **Prefer Fakes & Stubs:** Verifying state (e.g. `assert user.balance == 50`) tests _what_ the system produced, leaving internal implementation free to refactor.
- **Avoid Over-Mocking:** Verifying exact method call counts (`assert repo.query.call_count == 2`) tightly couples your test to private implementation details, creating brittle tests that break during simple refactoring.
