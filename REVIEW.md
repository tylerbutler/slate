# Slate Fleet Review

**Date**: 2026-03-23 (updated 2026-03-29)
**Scope**: Full codebase review of `slate` (Erlang FFI, Gleam API, Tests, Docs, Architecture)
**Status**: Synthesized from 6 parallel agent reports. Updated after decoder PR review.

## Executive Summary

`slate` is a high-quality, type-safe wrapper for Erlang's DETS. The core implementation is correct, robust, and idiomatic. Recent work added mandatory decoders for runtime type safety, a bounded atom pool, and improved lifecycle management.

---

## ✅ Resolved

### 1. Atom Exhaustion Risk — RESOLVED
- **Resolution**: A bounded pool of 4096 DETS table-name atoms (`TABLE_NAME_POOL_SIZE`) replaced unbounded `binary_to_atom/2` calls. See `src/dets_ffi.erl`.

### 2. Broken Documentation Examples — RESOLVED
- **Resolution**: `README.md` and all module doc examples updated to include `key_decoder` and `value_decoder` parameters.

### 3. `efbig` Error Mapping — RESOLVED
- **Resolution**: `{file_error, _, efbig}` is mapped to `file_size_limit_exceeded` in `dets_ffi.erl`.

---

## ⚠️ Remaining Improvements

### 1. Code Duplication
- **Severity**: Medium (Maintenance)
- **Location**: `src/slate/{set,bag,duplicate_bag}.gleam`
- **Status**: Partially addressed — `tuple_decoder` and `decode_entries` extracted to `src/slate/internal.gleam`. Remaining duplication in lifecycle management (`open`, `close`, `sync`, `with_table`) and fold wrappers could be further consolidated.

### 2. `bag.insert` vs `bag.insert_list` Semantics
- **Location**: `src/slate/bag.gleam`
- **Status**: Documented — `bag.insert` rejects duplicate objects with `KeyAlreadyPresent`, while `bag.insert_list` uses native DETS batch insert that silently deduplicates. Both behaviors are now documented in their respective doc comments.

### 3. ForceRepair Safety
- **Severity**: Low
- **Issue**: `ForceRepair` can silently overwrite/corrupt non-DETS files. A pre-open `is_dets_file` check could prevent this.

---

## ℹ️ Nits

- **Target Visibility**: Explicitly state "Erlang Target Only" in the README header. ✅ Done.
- **`internal_modules`**: `gleam.toml` now uses `slate/internal`. ✅ Done.

---

## Action Plan

1. ~~Fix README~~ ✅
2. ~~Safety Warning (atom pool)~~ ✅
3. ~~Extract shared code to internal module~~ ✅ (partial)
4. ~~Fix `bag.insert`/`insert_list` doc inconsistency~~ ✅
5. Consider further deduplication of lifecycle code across table modules.
6. Consider adding `is_dets_file` guard to `ForceRepair` path.
