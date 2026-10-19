---
title: "Value vs Reference, Pointers & Mutability"
description: "Passing data by value vs by reference, understanding pointers with simple analogies, and how mutable vs immutable data affects software design."
tags:
  - architecture
  - programming-concepts
  - pointers
  - mutability
date: 2026-10-19
---

# Value vs Reference, Pointers & Mutability 🎯

One of the most frequent sources of unexpected bugs is not knowing whether a variable holds an **actual copy** of data or a **pointer/reference** to shared data.

---

## 1. The Real-World Analogy: Photocopier vs Google Doc

- **Pass-by-Value (The Photocopier):** You take a printed document, photocopy it, and hand the copy to a teammate. If they highlight text or spill coffee on their copy, your original document is 100% untouched.
- **Pass-by-Reference / Pointer (The Google Doc URL):** You send a teammate a link to a shared Google Doc. If they change a paragraph, you instantly see that change in your browser because you are both editing the **exact same document**.

```
PASS-BY-VALUE:
Original: [ 42 ] ──(Copy)──▶ Function Param: [ 42 ] (Independent copy)

PASS-BY-REFERENCE / POINTER:
Original Variable ──┐
                    ├──▶ Shared Memory [ Alice, Admin ] (Both see changes)
Function Param    ──┘
```

---

## 2. Pointers Explained in Plain English

A **pointer** is simply a variable whose value is the **memory address** of another variable.

Think of it like a piece of paper with someone's home address written on it:

- The **value** is the physical house (with furniture, rooms).
- The **pointer** is the slip of paper saying `"123 Maple Street"`.
- Passing the slip of paper around is lightweight (only 8 bytes). Anyone holding the address can visit the house and change the furniture (**dereferencing**).

### Example in Go

```go
package main

import "fmt"

func updatePrice(price int) {
	price = 200 // Modifies a local copy!
}

func updatePriceWithPointer(pricePtr *int) {
	*pricePtr = 200 // Follows the address and modifies the original house!
}

func main() {
	itemPrice := 100

	updatePrice(itemPrice)
	fmt.Println(itemPrice) // 100 (Unchanged!)

	updatePriceWithPointer(&itemPrice) // & gets the address of itemPrice
	fmt.Println(itemPrice) // 200 (Modified!)
}
```

- `&x` means: _"Give me the memory address of `x`."_
- `*ptr` means: _"Go to the address inside `ptr` and read/write the value there."_

---

## 3. The "Pass-by-Sharing" Trap in Python and JavaScript

In Python, JavaScript, and Java, you don't write explicit `*` or `&` syntax. Instead:

- Primitive values (numbers, booleans, strings) behave like **values**.
- Collections and objects (lists, dictionaries, objects) behave like **shared references**.

### The Classic Shared Mutation Bug

```python
def add_admin_role(user_roles):
    user_roles.append("admin")  # Mutates the caller's list!

current_roles = ["editor"]
add_admin_role(current_roles)

print(current_roles)  # Output: ['editor', 'admin'] — surprising side-effect!
```

### The Default Argument Trap in Python

In Python, default arguments are created **once when the file loads**, not every time the function runs:

```python
# ❌ BUG: The same list is shared across every call!
def register_user(username, tags=[]):
    tags.append(username)
    return tags

print(register_user("alice")) # ['alice']
print(register_user("bob"))   # ['alice', 'bob'] ⚠️ Alice's tag leaked to Bob!

# ✅ FIX: Use None as default and create a fresh list inside
def register_user_safe(username, tags=None):
    if tags is None:
        tags = []
    tags.append(username)
    return tags
```

---

## 4. Mutable vs Immutable Data

| Quality        | Mutable Data                                         | Immutable Data                                           |
| :------------- | :--------------------------------------------------- | :------------------------------------------------------- |
| **Definition** | Can be changed in place after creation               | Cannot be modified once created                          |
| **Examples**   | Python `list`, `dict`; Go `slice`, `map`; JS `Array` | Python `tuple`, `str`, `int`; Go `string`; Java `String` |
| **Pros**       | Fast in-place updates, memory efficient              | Thread-safe, predictable, easy to reason about           |
| **Cons**       | Unintended side effects across functions             | Changing a value requires creating a new copy            |

### Why Modern Systems Love Immutability

In concurrent or distributed programming (like multiple threads or goroutines handling web requests), **immutable data requires zero mutexes or locks**. If no thread can modify a piece of data, dozens of threads can read it simultaneously with zero risk of corrupted data!

---

## Across the Wiki

- [[Architecture/programming-concepts/stack-heap-and-stack-overflow|Stack vs Heap Memory]] — How pointers connect stack variables to heap objects.
- [[Architecture/programming-concepts/garbage-collection-basics|Garbage Collection Basics]] — When data without any references gets reclaimed.
- [[Architecture/languages/golang/methods|Go Methods]] — Choosing between value receivers and pointer receivers.
