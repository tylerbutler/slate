---
title: Exclusive sessions across processes
description: Serialize short DETS sessions between independent BEAM VMs.
---

Use `with_exclusive_table` when CLI commands in separate BEAM VMs share a DETS
file. Each session acquires an OS lock, opens the current table, runs your
callback, closes DETS, then releases the lock. The helper returns `Ok(value)`
only after close and release succeed.

```gleam
import gleam/dynamic/decode
import slate
import slate/exclusive
import slate/set

use table <- set.with_exclusive_table(
  path: "data/cache.dets",
  repair: slate.AutoRepair,
  access: slate.ReadWrite,
  wait: exclusive.WaitUpTo(1000),
  key_decoder: decode.string,
  value_decoder: decode.string,
)
set.insert(table, "package", "metadata")
```

Create the parent directory first. The same helper exists in `slate/bag` and
`slate/duplicate_bag`, with their own typed handles and lookup return types.

## Two sessions around network work

1. Take a locked read session. Read cached entries, close DETS, and release
   ownership.
2. Fetch missing metadata without a table or lock.
3. Take a new locked write session. Insert fetched entries into the current
   table, close DETS, and release ownership.

Competing commands can fetch in parallel and take turns for storage access.
Do not replace the current table with a snapshot from step 1. Different-key
inserts accumulate across sessions.

Ordinary set inserts use last-write-wins for the same key. Keep a freshness
check, comparison, and conditional insert inside one callback if an older
network response must not replace newer data. Keep a read-modify-write sequence
inside one session:

```gleam
import gleam/dynamic/decode
import gleam/result
import slate
import slate/exclusive
import slate/set

use table <- set.with_exclusive_table(
  path: "data/counters.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  wait: exclusive.WaitUpTo(1000),
  key_decoder: decode.string, value_decoder: decode.int,
)
let current = case set.lookup(table, "count") {
  Ok(value) -> Ok(value)
  Error(slate.NotFound) -> Ok(0)
  Error(error) -> Error(error)
}
use value <- result.try(current)
set.insert(table, "count", value + 1)
```

Releasing ownership between the read and write permits lost updates.

## Acquisition waits and errors

`Immediate` tries once. `WaitUpTo(milliseconds)` retries contention until one
monotonic deadline; zero means immediate and a negative value returns
`InvalidWait`. There is no infinite-wait option. Slate runs native filesystem
work on BEAM dirty I/O schedulers.

The wait bounds contention retries. OS filesystem calls and BEAM scheduling
can delay the result; it is not a hard wall-clock limit on a stalled syscall.
Slate retries at intervals of at most 20 ms. A late acquisition after the
deadline releases its lock without opening DETS.

Once Slate acquires ownership, the deadline does not limit open, repair, or the
callback, and does not expire the lock.

```gleam
import gleam/io
import slate/exclusive

case session_result {
  Ok(value) -> Ok(value)
  Error(exclusive.AcquisitionFailed(exclusive.Busy)) -> {
    io.println("Cache busy; continuing without this cache result.")
    Error(exclusive.AcquisitionFailed(exclusive.Busy))
  }
  Error(exclusive.AcquisitionFailed(exclusive.TimedOut)) -> {
    io.println("Cache wait expired; continuing without this cache result.")
    Error(exclusive.AcquisitionFailed(exclusive.TimedOut))
  }
  Error(error) -> {
    io.println(exclusive.error_message(error))
    Error(error)
  }
}
```

These acquisition errors occur before DETS opens or the callback runs.
Applications can skip caching and report a warning. Other acquisition failures
include unsupported targets/filesystems, missing native code, unsafe aliases,
and OS errors. Slate does not use an unlocked fallback.

The callback returns `Result(a, slate.DetsError)`. The helper returns
`Result(a, exclusive.SessionError)`:

| Error | Meaning |
|-------|---------|
| `AcquisitionFailed(error)` | Ownership acquisition failed |
| `SessionFailed(OpenFailure(error))` | DETS open or repair failed |
| `SessionFailed(CallbackFailure(error))` | Callback returned a storage error |
| `CleanupFailed(primary, failures)` | Close, release, or guardian failure; retains any primary failure |

Use `exclusive.error_code` or `exclusive.error_message` for safe output.
Diagnostic paths and reasons belong in trusted logs. See
[error handling](/advanced/error-handling/#exclusive-session-errors).

## Caller death and cleanup recovery

The callback runs in the original calling process. A separate guardian owns
the DETS open and monitors that caller. On callback return or exception, Slate
waits for cleanup. On caller death, the guardian closes DETS before releasing
ownership. Slate confirms that the underlying DETS server has stopped, not
just that one DETS user has closed.

If close fails, another DETS user keeps the server open, or the guardian dies,
Slate keeps the native lock unless it can confirm safe cleanup. Ownership can
remain until the VM exits. Treat `CleanupFailed` as a quarantine condition:
report the error and stop using that file in the surviving VM. Do not delete
the sidecar to recover it.

Callback exceptions retain their class, reason, and stacktrace. Slate re-raises
them after cleanup and logs cleanup failures. It also logs cleanup failures
when the caller dies, plus unexpected guardian termination. Logger reports
use `slate_exclusive_cleanup_failed` or `slate_exclusive_guardian_stopped` as
their `event` field.

VM exit or crash releases OS ownership without deleting the sidecar. The next
open may need DETS repair. `NoRepair` returns `NeedsRepair`;
`AutoRepair` attempts recovery under ownership. Back up a closed file before
repairing data you need to keep.

## Ownership restrictions

All clients of the shared file must use exclusive sessions, including readers
while writes can occur. Raw DETS, older Slate, and unlocked APIs ignore the
advisory lock. Exclusive sessions reject an already-open same-file table in
the VM. They serialize sessions; they do not permit simultaneous DETS access
from independent VMs.

Keep the handle and all table work inside the callback. Do not reopen or
close the table yourself, save the handle, or pass it to work that outlives the
callback. Nested same-file sessions contend for ownership; they are not
reentrant. Different files use independent locks.

A callback error does not roll back earlier inserts. Exclusive sessions add
no transaction or power-loss guarantee. Repair can lose data.

## Paths, sidecars, and filesystem limits

Slate resolves directory and file symlinks before choosing
`<resolved-data-path>.slate.lock` and passes the resolved path to DETS.
For a new file, the parent must exist. Relative, absolute, and supported
filesystem aliases use the same sidecar. Slate checks identity again under
ownership before opening DETS.

Existing data files must have one hard link. Slate rejects hard-linked data
files, dangling symlinks, and symlinked, hard-linked, or non-regular sidecars.
The sidecar persists across sessions and repair. Its presence does not mean
an owner exists; the OS lock determines ownership.

Keep the namespace trusted and stable. Do not rename, replace, or remove data
paths or sidecars, or create new links while clients can start sessions.
Hostile concurrent namespace mutation is outside the support contract.

Use only the [native release targets and allowed local filesystems](/installation/#exclusive-session-native-component).
Network, FUSE, and overlay mounts are unsupported. This protocol has same-host
scope. An escript needs the native companion directory described in
[installation](/installation/#erlang-shipments-and-escripts).

## Open and close overhead

One local Linux x64 measurement used OTP 27.3.4.13, a release native build,
local ext4 storage, and an existing set with 1,000 integer entries.
For 200 sequential, uncontended sessions with one lookup each, the shared
exclusive lifecycle took a median of 1.108 ms and a 95th percentile of
1.586 ms per session. The measurement included acquisition, DETS open,
lookup, close, and release, without Gleam decoder work.

These observations are not latency guarantees. File size, repair, pending
writes, storage, and contention can increase costs. Measure your workload
before choosing a long-lived owner service or another storage backend.
