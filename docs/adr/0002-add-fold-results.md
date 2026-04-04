# ADR-0002: Add fold_results for partial-failure bulk reads

## Status

Accepted

## Date

2026-04-04

## Context

Slate's `fold` and `to_list` operations short-circuit on the first
`DecodeError`. If a single record in a large DETS table has schema drift or was
written with a different type, the entire bulk read fails and all successfully
decodable records are lost.

This was raised in [#24](https://github.com/tylerbutler/slate/issues/24) as a
request for "safe" or "accumulating" variants of bulk read operations.

### Current behavior

Both `fold` and `to_list` use a fail-fast strategy:

- `to_list` calls `list.try_map` over decoded entries — stops at the first error.
- `fold` wraps the user callback so that a decode error returns
  `Error(DecodeErrors(...))`, which the FFI layer catches via
  `throw({slate_fold_abort, Err})` to immediately abort the `dets:foldl`
  iteration.

This is the correct default for the common case where all records should decode
cleanly.

### Gleam stdlib patterns

The stdlib provides three strategies for bulk operations:

| Strategy                  | Function            | Behavior                  |
| ------------------------- | ------------------- | ------------------------- |
| Fail-fast                 | `list.try_map`      | Stop at first error       |
| Keep successes only       | `list.filter_map`   | Silently discard errors   |
| Partition                 | `result.partition`  | Keep both sides           |

Rather than adding separate variants for each strategy, a single
`fold_results` function that passes `Result` values to the callback lets users
implement any of these strategies themselves.

## Decision

Add a `fold_results` function to `set`, `bag`, and `duplicate_bag`. Keep the
existing `fold` and `to_list` unchanged.

### Signature

```gleam
pub fn fold_results(
  over table: Set(k, v),
  from initial: acc,
  with fun: fn(acc, Result(#(k, v), List(decode.DecodeError))) -> acc,
) -> Result(acc, DetsError)
```

The callback receives `Result(#(k, v), List(decode.DecodeError))` for each
entry. Decode failures become `Error` values passed to the callback instead of
aborting the fold. The outer `Result` still captures DETS-level errors (table
does not exist, etc.).

### Why not `to_list_results`?

`fold_results` subsumes any `to_list` variant. Users can build exactly the
collection shape they need in the callback (list of successes, partitioned
tuple, count of errors, etc.). This keeps the API surface small.

## Consequences

- Users dealing with schema drift or mixed-type tables can recover healthy
  records without losing the entire read.
- The existing `fold` and `to_list` remain the simple, recommended default.
- No FFI changes required — the same `dets_ffi:fold/3` function is reused. The
  Gleam wrapper simply never returns an error result to the FFI, so it never
  triggers the abort path.
- Added to all three table modules to maintain API symmetry.

## Alternatives considered

1. **`to_list_safe` returning `List(Result(...))`** — Rejected. Less flexible
   than a fold, and would require a second function (`fold_safe`) for
   non-list accumulations.

2. **`to_list_lenient` that silently skips errors** — Rejected. Hiding errors
   by default is surprising. Users who want this behavior can trivially
   implement it with `fold_results`.

3. **Do nothing** — Rejected. There is no reasonable workaround without
   dropping to raw Erlang FFI calls, which defeats the purpose of the library.
