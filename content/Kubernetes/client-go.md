---
title: client-go & Kubernetes Go SDK
tags: [kubernetes, go, client-go, sdk, controllers, apimachinery]
date: 2026-09-06
description: Guide and references for programmatically interacting with Kubernetes APIs using the client-go library.
---

# client-go (Kubernetes Go Client)

`client-go` is the official Go client library for communicating with the Kubernetes API server. It is used by `kubectl`, built-in controllers, and custom operator frameworks like Kubebuilder and Operator SDK.

## Core Concepts

- **Clientsets**: Typed interfaces generated for built-in Kubernetes API groups (`core/v1`, `apps/v1`, etc.).
- **Dynamic Client**: Generic client for working with arbitrary or custom resources (CRDs) without generated code.
- **Informers & SharedInformerFactory**: Caching watch loops that synchronize cluster state to local in-memory caches and dispatch event handlers (`AddFunc`, `UpdateFunc`, `DeleteFunc`).
- **Workqueue**: Rate-limiting, deduplicating work queues used in reconciliation loops.

## Related Internals

- [[Kubernetes/concepts/L09-advanced/01-operators|Operators]]: The controller pattern in depth.
- [[Kubernetes/concepts/L09-advanced/02-custom-controllers|Custom Controllers]]: Building custom reconcile loops with informers and workqueues.
- [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CRDs]]: Defining schema and API extensions.

## Resources & Documentation

- [Official client-go Repository](https://github.com/kubernetes/client-go)
- [Kubernetes API Machinery Documentation](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-api-machinery/controllers.md)
