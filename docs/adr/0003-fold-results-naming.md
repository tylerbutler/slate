# ADR-0003: Keep `fold_results` name instead of `try_fold`

## Status

Accepted

## Date

2026-04-07

## Context

During the pre-1.0 API review, the name `fold_results` was questioned. The
alternative `try_fold` was considered, following Rust's `Iterator::try_fold`
convention.

After 1.0, renaming a public function is a breaking change, so this decision
needed to be made now.

## Decision

Keep `fold_results`.

## Rationale

### `try_fold` has the wrong connotation

Rust's `try_fold` short-circuits on the first error — the "try" means "attempt,
and bail early if it fails." Slate's `fold_results` does the opposite: it
visits **every** entry regardless of decode failures. Naming it `try_fold` would
set the wrong expectation for users familiar with the Rust convention.

### `fold_results` describes the payload, not the control flow

The function's distinguishing characteristic is that each entry arrives as a
`Result(#(k, v), List(decode.DecodeError))` instead of a decoded `#(k, v)`.
The name `fold_results` communicates this directly: "fold, but the entries are
Results." This matches the Gleam pattern of naming functions after what they
produce or consume (`list.filter_map`, `result.partition`).

### The existing `fold` already returns a `Result`

Both `fold` and `fold_results` return `Result(acc, DetsError)` as their outer
type. The distinction is in the callback signature, not the return type. Naming
the variant `try_fold` would suggest the difference is in the outer Result
(try/fail), when the actual difference is in the inner entry type.

### ADR-0002 established the callback-receives-Result pattern

ADR-0002 chose the `fn(acc, Result(...)) -> acc` signature specifically so that
users could implement any error-handling strategy (skip, partition, count) in
the callback. The name `fold_results` aligns with this design: the function
folds over Result values.

## Alternatives considered

1. **`try_fold`** — Rejected. Implies short-circuit-on-error semantics (Rust
   convention), which is the opposite of this function's behavior.

2. **`fold_lenient`** — Rejected. Implies the function is less strict, but it
   doesn't actually change what errors are raised — it just passes them to the
   callback instead of aborting.

3. **`fold_all`** — Rejected. Ambiguous — could mean "fold over all tables" or
   "fold all entries." Less descriptive than `fold_results`.
