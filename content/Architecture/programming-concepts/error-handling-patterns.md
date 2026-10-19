---
title: "Error Handling: Exceptions vs Errors as Values"
description: "How software handles failure — try/catch exceptions vs Go-style errors as return values, failure propagation, and writing resilient code."
tags:
  - architecture
  - programming-concepts
  - error-handling
  - exceptions
date: 2026-10-19
---

# Error Handling: Exceptions vs Errors as Values ⚠️

Errors in software are inevitable: a database connection times out, a JSON payload is malformed, or a disk runs out of space. How a programming language handles failure fundamentally shapes how you write reliable, production-grade services.

There are two dominant philosophies in software engineering: **Exceptions (`try/catch`)** and **Errors as Values (`if err != nil`)**.

---

## 1. Model A: Exceptions (`try / catch / finally`)

Languages like Python, JavaScript, Java, and C# use **Exceptions**. When an error occurs, the runtime halts the current function and unwinds the call stack until it finds an enclosing `try/catch` block.

```python
def read_user_profile(user_id):
    try:
        user = db.fetch_user(user_id)         # Might raise DatabaseError
        settings = parse_json(user['config'])  # Might raise JSONDecodeError
        return settings
    except DatabaseError as e:
        logger.error(f"Database query failed: {e}")
        return default_settings()
    except Exception as e:
        logger.critical(f"Unexpected crash: {e}")
        raise  # Re-raise to caller
    finally:
        db.release_connection()  # ALWAYS runs, even if an error happened!
```

### Strengths & Weaknesses of Exceptions

| Pros                                                             | Cons                                                                                                                |
| :--------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------ |
| Separates normal "happy path" logic from error recovery code     | **Invisible control flow:** It is hard to tell which function calls can throw an exception just by reading the code |
| Errors can easily bubble up multiple layers to a central handler | Developers often write sloppy `except Exception: pass`, silently swallowing bugs                                    |
| `finally` ensures cleanup happens reliably                       | Raising exceptions has slight CPU overhead during stack unwinding                                                   |

---

## 2. Model B: Errors as Values (Go, Rust)

Languages like **Go** and **Rust** treat errors not as special runtime-interrupting events, but as **normal return values**:

```go
package main

import (
	"errors"
	"fmt"
	"os"
)

// In Go, functions return (result, error)
func loadConfig(path string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		// Wrap error with helpful context and return early!
		return nil, fmt.Errorf("loadConfig failed for %s: %w", path, err)
	}
	return data, nil
}

func main() {
	config, err := loadConfig("/etc/app/config.json")
	if err != nil {
		fmt.Printf("Fatal error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Config loaded: %d bytes\n", len(config))
}
```

### Strengths & Weaknesses of Errors as Values

| Pros                                                                            | Cons                                                   |
| :------------------------------------------------------------------------------ | :----------------------------------------------------- |
| **Completely explicit:** You know exactly where errors can happen on every line | Requires writing repetitive `if err != nil` checks     |
| No invisible surprises: Errors cannot silently jump past your code              | Can make functions feel verbose                        |
| Excellent performance: No stack unwinding overhead                              | Forgetting to check `err` can cause nil pointer panics |

---

## 3. Four Golden Rules for Production Error Handling

Regardless of which language you use, follow these four rules when handling errors:

### 1. Fail Fast

Validate inputs at the very start of a function. Return early if an input is invalid so you don't perform unnecessary work:

```python
def withdraw(account_id, amount):
    if amount <= 0:
        raise ValueError("Withdrawal amount must be positive")
    # ... proceed with business logic ...
```

### 2. Add Context When Propagating

Never return a bare error like `"file not found"`. Add context explaining **what the system was trying to do**:

- ❌ _"file not found"_
- ✅ _"failed to load payment provider keys from /etc/secrets/stripe.key: file not found"_

### 3. Never Swallow Errors Silently

Never catch an error and do nothing:

```python
# ❌ DANGEROUS: Silent failure makes debugging in production impossible!
try:
    send_confirmation_email(user)
except Exception:
    pass  # "I'm sure it's fine" (It was not fine.)
```

### 4. Panics / Crashes are for Programmer Bugs, Not Expected Failures

- An invalid user password is an **expected condition** $\rightarrow$ Return an error.
- A database network timeout is an **expected operational failure** $\rightarrow$ Return an error or retry.
- A `nil` pointer dereference or index out of bounds is a **programmer bug** $\rightarrow$ Crash / panic immediately.

---

## Across the Wiki

- [[Architecture/solution-architecture-concepts/software-engineering-concepts/api-error-codes|API Error Codes & RFC 7807]] — How backend services communicate errors over HTTP.
- [[Architecture/solution-architecture-concepts/reliability/resilience|Resilience & Circuit Breakers]] — Graceful degradation when dependent services fail.
- [[Architecture/languages/golang/README|Go Systems Architecture]] — Idiomatic Go error handling and wrapping patterns.
