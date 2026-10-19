---
title: "Variable Scope, Closures & Callbacks"
description: "How variable scope works, passing functions as arguments (callbacks), and closures explained with clear mental models and code examples."
tags:
  - architecture
  - programming-concepts
  - closures
  - callbacks
  - scope
date: 2026-10-19
---

# Variable Scope, Closures & Callbacks 🎒

When building backend services, you frequently need to pass logic around—such as authentication middleware, event handlers, or retry logic. Understanding **Scope**, **Callbacks**, and **Closures** is essential for reading and writing clean asynchronous and modular code.

---

## 1. Scope: Where Can a Variable Be Seen?

**Scope** determines where in your code a variable is accessible.

```python
# 1. GLOBAL SCOPE: Accessible anywhere in the file
DATABASE_URL = "postgres://localhost:5432"

def process_order(order_id):
    # 2. LOCAL (FUNCTION) SCOPE: Only exists inside process_order()
    tax_rate = 0.08

    if order_id > 1000:
        # 3. BLOCK SCOPE: Inside this if statement (in languages like Go, JS, C)
        discount = 10
        print(f"Applying discount of ${discount}")

    # print(discount) -> In Go/C/Java, this is a compiler error (out of block scope!)

process_order(1050)
# print(tax_rate) -> ❌ Error: tax_rate does not exist outside the function!
```

> **Best Practice:** Keep scopes as small as possible. Global variables create hidden coupling between functions and make concurrent programs prone to data races.

---

## 2. First-Class Functions & Callbacks

In languages like JavaScript, Python, Go, and Rust, **functions are first-class citizens**. This simply means you can treat a function like any other variable:

- Assign it to a variable.
- Pass it as an argument to another function (**Callback**).
- Return it from another function.

### What is a Callback?

A **callback** is a function you pass to another function to be called back later:

```python
def fetch_user_data(user_id, on_success):
    print(f"Fetching data for user {user_id}...")
    user = {"id": user_id, "name": "Alice"}
    # Call the callback function that the caller provided!
    on_success(user)

def handle_user(user):
    print(f"Welcome back, {user['name']}!")

fetch_user_data(42, handle_user)
```

Callbacks are everywhere: array filtering (`filter(fn)`), HTTP request handlers, and event listeners.

---

## 3. Closures: "A Function with a Backpack"

A **Closure** is a function that **remembers and has access to variables from its outer (enclosing) scope**, even after the outer function has finished running!

### The Backpack Analogy

Think of a normal function like a traveler with empty pockets. When it finishes its journey, it forgets everything.

A **closure** is a traveler wearing a **backpack**. When created inside an outer function, it packs whatever outer variables it needs into its backpack and carries them with it wherever it goes!

```python
def create_counter(start_at=0):
    count = start_at  # Packed into the backpack!

    def increment():
        nonlocal count
        count += 1
        return count

    return increment  # Returns the inner function WITH its backpack!

# 'create_counter' finishes, but its backpack stays alive with 'counter_a'!
counter_a = create_counter(10)
counter_b = create_counter(100)

print(counter_a()) # 11
print(counter_a()) # 12
print(counter_b()) # 101 (Has its own independent backpack!)
```

### Real-World Use Case: Configurable Middleware / Decorators

In web frameworks like Go's `net/http` or Python's `FastAPI`/`Flask`, closures allow you to create reusable wrappers for rate limiting, logging, or authentication:

```go
package main

import "fmt"

// Closure that generates a custom rate limiter
func makeRateLimiter(maxRequests int) func() bool {
	requestsSoFar := 0
	return func() bool {
		if requestsSoFar >= maxRequests {
			return false // Rate limit exceeded!
		}
		requestsSoFar++
		return true
	}
}

func main() {
	allowRequest := makeRateLimiter(2)
	fmt.Println(allowRequest()) // true (1/2)
	fmt.Println(allowRequest()) // true (2/2)
	fmt.Println(allowRequest()) // false (Blocked!)
}
```

---

## 4. The Classic Closure Trap: Loop Variables

A notorious trap in JavaScript, Python, and older versions of Go occurs when creating closures inside a loop:

```python
handlers = []
for i in range(3):
    handlers.append(lambda: print(i)) # Grabs the variable 'i'

for h in handlers:
    h() # ⚠️ Prints: 2, 2, 2 (NOT 0, 1, 2!)
```

- **Why?** The closures didn't store the _value_ of `i` at that moment; they held a reference to the single variable `i`, which ended up as `2` when the loop finished.
- **Fix in modern Python:** Use a default argument to snapshot the value: `lambda i=i: print(i)`.

---

## Across the Wiki

- [[Architecture/languages/golang/closures|Go Closures & Concurrency]] — Deep dive into closures inside goroutines.
- [[Architecture/languages/python/decorators|Python Decorators]] — How Python uses closures for `@decorator` syntax.
- [[Architecture/programming-concepts/sync-vs-async-programming|Sync vs Async Programming]] — How callbacks evolved into `async`/`await`.
