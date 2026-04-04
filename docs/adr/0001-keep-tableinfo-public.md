# ADR-0001: Keep TableInfo as a public record type

## Status

Accepted

## Date

2026-04-04

## Context

Before the 1.0 release, we needed to decide whether `TableInfo` should remain a
public (matchable) record or become an opaque type with accessor functions.

`TableInfo` is currently defined as:

```gleam
pub type TableInfo {
  TableInfo(file_size: Int, object_count: Int, kind: Kind)
}
```

Making it opaque before 1.0 would allow adding fields later without a breaking
change. Keeping it public commits to this exact shape for the 1.x line.

This decision was tracked in [#43](https://github.com/tylerbutler/slate/issues/43).

## Decision

Keep `TableInfo` as a public record type.

## Rationale

### The Gleam ecosystem convention: handles are opaque, data is public

We surveyed the type design of major Gleam libraries and found a consistent
pattern:

| Category            | Opacity | Examples                                                   |
| ------------------- | ------- | ---------------------------------------------------------- |
| **Resource handles** | Opaque  | `gleam/set.Set`, `gleam_otp/actor.Builder`, slate's `Set(k,v)` |
| **Data records**     | Public  | `simplifile.FileInfo`, `gleam_otp/actor.Started`, `gleam/uri.Uri` |
| **Error types**      | Public  | `DetsError`, `simplifile.FileError`, `snag.Snag`           |
| **Config enums**     | Public  | `AccessMode`, `RepairPolicy`, `glint.ArgsCount`            |

Opaque types are reserved for values where:

1. The type wraps FFI or runtime handles users should not touch.
2. There are construction invariants that arbitrary field values would violate
   (e.g., `gleam_time/Duration` normalizes nanoseconds).
3. The internal representation may change independently of the API.

`TableInfo` meets none of these criteria — it is read-only data with no
invariants.

### The closest analog is `simplifile.FileInfo`

`simplifile.FileInfo` is a 10-field public record returned from `file_info()`.
It serves the same role as `TableInfo`: a stats/metadata snapshot of a
filesystem resource. It is public, not opaque, and provides helper functions
that operate on the public type rather than accessor functions that hide it.

### Future extension risk is low

Erlang's DETS only exposes two additional info fields beyond what `TableInfo`
already surfaces:

- `keypos` — always 1 for DETS; an implementation detail.
- `filename` — already known to the caller from the open path.

The DETS API surface has been essentially frozen for years. The likelihood of
needing to extend `TableInfo` is minimal.

### Slate's existing type surface is already consistent

| Type                | Opaque | Role          |
| ------------------- | ------ | ------------- |
| `Set(k,v)`          | Yes    | Table handle  |
| `Bag(k,v)`          | Yes    | Table handle  |
| `DuplicateBag(k,v)` | Yes    | Table handle  |
| `DetsError`          | No     | Error enum    |
| `Kind`               | No     | Data enum     |
| `AccessMode`         | No     | Config enum   |
| `RepairPolicy`       | No     | Config enum   |
| `UpdateCounterError` | No     | Error enum    |
| `TableInfo`          | No     | Data record   |

All handle types are opaque; all data, config, and error types are public. No
changes are needed.

### bravo (Gleam ETS wrapper) follows the same pattern

bravo uses opaque types for table handles (`USet`, `Bag`, `OSet`, `DBag`) and
public types for configuration and errors (`BravoError`, `Access`, `Spec`). It
does not expose a table info type, but its handle-vs-data split matches slate's.

## Consequences

- `TableInfo` remains a public record with `file_size`, `object_count`, and
  `kind` fields.
- Users may access fields directly (e.g., `info.object_count`) and pattern
  match on the constructor.
- Adding a field to `TableInfo` after 1.0 would be a breaking change — this is
  accepted given the low likelihood of needing to do so.
- No accessor functions are needed.

## Alternatives considered

1. **Make `TableInfo` opaque with accessor functions** — Rejected. Adds
   boilerplate without meaningful benefit. Inconsistent with how the Gleam
   ecosystem treats small data return types.

2. **Add likely future fields now (access mode, path, repair state)** —
   Rejected. These are either already available through other means or are
   implementation details not useful to consumers.
