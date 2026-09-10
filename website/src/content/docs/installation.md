---
title: Installation
description: How to install slate in your Gleam project.
---

Add slate to your Gleam project:

```bash
gleam add slate
```

This adds slate to your `gleam.toml` dependencies. slate supports Gleam's Erlang target, which runs on the BEAM. It does not support the JavaScript target.

## Requirements

- **Gleam** >= 1.7.0
- **Erlang/OTP** >= 26 (recommended: 27+)
- **Target**: Erlang only

## Dependencies

Gleam also installs these packages:

| Package | Purpose |
|---------|---------|
| `gleam_stdlib` | Standard library |
| `gleam_erlang` | Erlang interoperability |

## Upgrading

See the [changelog](https://github.com/tylerbutler/slate/blob/main/CHANGELOG.md) for release history and breaking changes. See [Stability and versioning](/advanced/stability/) for the versioning policy.
