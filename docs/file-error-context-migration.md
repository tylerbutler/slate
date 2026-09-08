# File error context migration (breaking)

Seven existing `slate.DetsError` constructors now carry one `FileErrorContext`:

```gleam
FileNotFound(FileErrorContext)
AlreadyOpen(FileErrorContext)
AccessDenied(FileErrorContext)
TypeMismatch(FileErrorContext)
NeedsRepair(FileErrorContext)
NotADetsFile(FileErrorContext)
FileSizeLimitExceeded(FileErrorContext)
```

The shared record is:

```gleam
pub type FileErrorContext {
  FileErrorContext(path: Option(String), reason: String)
}
```

## Update patterns

Before:

```gleam
let assert Error(slate.AccessDenied) = set.insert(table, "key", "value")
let assert Error(slate.NeedsRepair) =
  set.open_with(path, slate.NoRepair,
    key_decoder: decode.string, value_decoder: decode.string)
```

After, if you only need the category:

```gleam
let assert Error(slate.AccessDenied(_)) = set.insert(table, "key", "value")
let assert Error(slate.NeedsRepair(_)) =
  set.open_with(path, slate.NoRepair,
    key_decoder: decode.string, value_decoder: decode.string)
```

Use the same `(context)` or `(_)` pattern for all seven constructors. For example,
change `Error(slate.AlreadyOpen)` to `Error(slate.AlreadyOpen(context))`. For counters,
change `Error(set.TableError(slate.AccessDenied))` to
`Error(set.TableError(slate.AccessDenied(context)))`.

To inspect context:

```gleam
import gleam/option.{None, Some}

let assert Error(slate.AccessDenied(context)) = set.insert(table, "key", "value")
case context.path {
  Some(path) -> {
    // Send path and context.reason only to a trusted diagnostic sink.
    #(Some(path), context.reason)
  }
  None -> #(None, context.reason)
}
```

## Update constructed errors

Before:

```gleam
let error = slate.AccessDenied
```

After:

```gleam
import gleam/option.{None}

let error = slate.AccessDenied(
  slate.FileErrorContext(path: None, reason: "application denied write"),
)
```

Use `Some(actual_path)` when you know the filename. Use `None` when you do not;
do not insert an empty string or guess a path. To pass a constructor as a
callback that previously returned a bare error, use a function that constructs
the record, or propagate the original error unchanged.

## Context contract

- `path` is the filename in the OTP error, not an internal table-name atom.
  Opens normally report the absolute, normalized path that slate passes to OTP.
  For a pathless `incompatible_arguments` error during open, slate retains that
  known path in `AlreadyOpen(context)` instead of discarding it.
  `is_dets_file` can report the relative path given by the caller. Do not assume
  every operation reports the same spelling or that symlinks are resolved.
- `None` is used for pathless OTP errors, including bare `needs_repair` and
  `not_a_dets_file` reasons. For a rename failure with two filenames, `path` is
  `None` and `reason` retains the full file error, including both filenames;
  slate does not choose a misleading single path.
  Context does not query table metadata after a failure.
  Closing a table, losing its owner, or reusing a pool slot cannot change an
  error value that has already been returned.
- `reason` is diagnostic text, not a stable classifier. File-system errors keep
  their lower-level reason, for example `"enoent"` or `"{error,eacces}"`.
  Other errors retain their OTP tag, such as `"access_mode"`,
  `"type_mismatch"`, `"keypos_mismatch"`, `"incompatible_arguments"`, or `"needs_repair"`.
  No expected/actual table type is invented when OTP supplies neither.
- The DETS allocator's `no_more_space_on_file` reason maps to
  `FileSizeLimitExceeded`, as does the existing `efbig` file error.
- Unknown reasons remain `UnexpectedError`; they are not silently treated as
  access failures. For example, disk-full `enospc` is not the DETS 2 GB limit.
- Both fields can contain sensitive paths or other diagnostic details. Do not
  send them directly to users. Every `error_code` and `error_message` output is
  unchanged and excludes the new context.

## What does not change

`NotFound`, `KeyAlreadyPresent`, `DecodeErrors`, and all other error variants
keep their existing shapes and meanings. `TableDoesNotExist` does not gain a
fabricated file path. A second `close` can still return
`UnexpectedError("not_owner")`; this change does not redefine ownership errors.

The `Set`, `Bag`, and `DuplicateBag` handles and operation signatures are
unchanged. All three modules use the same FFI translation. Counter errors still
use `set.TableError` for shared DETS failures. `with_table` still returns the
callback error if both the callback and close fail.

This is a **source and in-memory error representation break**, not an on-disk
table-format change. Rebuild callers and update stored/serialized `DetsError`
values if your application persists them as data. Ordinary DETS key/value
records do not need migration.

## Storage and lifecycle limits

This change adds diagnostics, not recovery or transactions. A write or close
error does not prove that no data reached disk; avoid blind retries of
non-idempotent writes. Keep backups before repair, since repair can recover only
part of a damaged file. Close each successful open, and use a supervised owner
process for long-lived tables. Context does not keep tables open or create atoms
from paths; the bounded table-name pool is unchanged.

DETS remains the disk-backed choice with a 2 GB file limit and disk I/O costs.
ETS can reduce read latency but does not persist data by itself. Mnesia can add
transactions and distribution but requires a different storage and ownership
design. Neither is needed to retain file-error diagnostics.
