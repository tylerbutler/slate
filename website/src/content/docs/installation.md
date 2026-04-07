---
title: Installation
description: How to install slate in your Gleam project.
---

Add slate to your Gleam project:

```bash
gleam add slate
```

This adds slate to your `gleam.toml` dependencies. slate targets the **Erlang (BEAM)** runtime — it does not support the JavaScript target.

## Requirements

- **Gleam** >= 1.7.0
- **Erlang/OTP** >= 26 (recommended: 27+)
- **Target**: Erlang only

## Dependencies

slate brings in these Gleam packages automatically:

| Package | Purpose |
|---------|---------|
| `gleam_stdlib` | Standard library |
| `gleam_erlang` | Erlang interop |

## Upgrading

See the [CHANGELOG](https://github.com/tylerbutler/slate/blob/main/CHANGELOG.md) for release history and breaking changes, and the [Stability & Versioning](/advanced/stability/) page for semver guarantees.
