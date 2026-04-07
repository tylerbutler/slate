# ADR-0004: Keep `UpdateCounterError` on `slate/set` instead of merging into `DetsError`

## Status

Accepted

## Date

2026-04-07

## Context

`set.update_counter` returns `Result(Int, UpdateCounterError)` where
`UpdateCounterError` has two variants:

```gleam
pub type UpdateCounterError {
  CounterValueNotInteger
  TableError(DetsError)
}
```

During the pre-1.0 API review, two alternatives were considered:

1. Move `CounterValueNotInteger` into `DetsError` so that `update_counter`
   returns `Result(Int, DetsError)` like every other operation.
2. Move `UpdateCounterError` to `slate.gleam` so it can be shared if
   `update_counter` is later added to bag/duplicate_bag modules.

After 1.0, changing the error type of a public function is a breaking change,
so this decision needed to be made now.

## Decision

Keep `UpdateCounterError` as a type on `slate/set`.

## Rationale

### `CounterValueNotInteger` does not belong in `DetsError`

`DetsError` represents errors that can occur on any DETS operation across all
table types. `CounterValueNotInteger` is specific to a single operation
(`update_counter`) on a single table type (`set`). Adding it to `DetsError`
would mean:

- Every exhaustive `case` on `DetsError` across the entire codebase would need
  a `CounterValueNotInteger` arm, even in code that never calls
  `update_counter`.
- The variant would be unreachable from every operation except `update_counter`,
  making `DetsError` a less honest type.

### A separate error type provides stronger type-level guidance

With the current design, the type signature `Result(Int, UpdateCounterError)`
tells the caller exactly which error cases are possible. A caller matching on
`UpdateCounterError` knows there are exactly two arms to handle. If the error
were `DetsError`, the caller would see 12+ variants and need to reason about
which ones are actually reachable from `update_counter`.

### `update_counter` is unlikely to be added to bag/duplicate_bag

`dets:update_counter/3` operates on the single value associated with a key.
For bag and duplicate_bag tables, a key maps to multiple values, making the
semantics of "increment the counter for key X" ambiguous. Even in Erlang,
`update_counter` on a bag table updates only the first object and is rarely
used. Exposing it for bags would require either arbitrary-seeming behavior or a
significantly different API. The set-only restriction is a deliberate design
choice, not an omission.

### Moving to `slate.gleam` is premature

If `update_counter` were later added to other table types, `UpdateCounterError`
could be moved to `slate.gleam` at that time. Since that move would only add a
re-export (the type itself wouldn't change), it could be done in a
backward-compatible way by keeping a type alias on `slate/set`. There is no
need to move it preemptively.

## Consequences

- `update_counter` callers match on `set.CounterValueNotInteger` and
  `set.TableError(dets_error)`.
- Code that handles `DetsError` does not need to account for counter-specific
  errors.
- If a future version adds counter support to other table types, the type can
  be lifted to `slate.gleam` with a backward-compatible alias.

## Alternatives considered

1. **Merge `CounterValueNotInteger` into `DetsError`** — Rejected. Pollutes a
   shared error type with an operation-specific variant. Forces unnecessary
   match arms on all `DetsError` consumers.

2. **Move `UpdateCounterError` to `slate.gleam` now** — Rejected. Premature
   generalization. The type is currently used by one function in one module.
   Can be moved later if needed without breaking changes.
