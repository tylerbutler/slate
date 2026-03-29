# Slate Fleet Review

**Date**: 2026-03-23
**Scope**: Full codebase review of `slate` (Erlang FFI, Gleam API, Tests, Docs, Architecture)
**Status**: Synthesized from 6 parallel agent reports.

## Executive Summary

`slate` is a high-quality, type-safe wrapper for Erlang's DETS. The core implementation is correct, robust, and idiomatic. However, it suffers from **significant code duplication** across the three table types and has a **critical safety issue** regarding dynamic file paths causing atom exhaustion. Documentation needs immediate fixes for compiling examples.

---

## 🚨 Critical Findings

### 1. Atom Exhaustion Risk (DoS)
- **Severity**: Critical
- **Location**: `src/dets_ffi.erl:33` (`binary_to_atom(Path, utf8)`)
- **Issue**: The library converts every file path to an Erlang atom. Atoms are **never garbage collected**. Opening tables with unbounded dynamic paths (e.g., user-generated filenames) will exhaust the VM's atom limit (default ~1M), causing a crash.
- **Action**:
    - **Immediate**: Add a prominent warning in `README.md` and `src/slate.gleam` against using dynamic paths.
    - **Long-term**: Investigate using a fixed pool of workers or a registry to avoid one-atom-per-path if possible (DETS constraint makes this hard).

### 2. Broken Documentation Examples
- **Severity**: Critical
- **Location**: `README.md`
- **Issue**: The `Usage` examples fail to compile. They call `set.open("file.dets")` but the API requires `key_decoder` and `value_decoder` arguments.
- **Action**: Update `README.md` to match the actual API and include necessary imports (`gleam/dynamic/decode`).

### 3. Code Duplication
- **Severity**: High (Maintenance)
- **Location**: `src/slate/{set,bag,duplicate_bag}.gleam`
- **Issue**: ~80% of the code is identical across the three modules. Lifecycle management (`open`, `close`, `sync`), deletion, and internal helpers are copy-pasted.
- **Action**: Extract shared logic to `src/slate/internal.gleam`.
    - Move `tuple_decoder`, `decode_entries`.
    - Create generic `with_table`, `fold`, `close`, `sync` wrappers.

---

## ⚠️ Improvements

### 1. Error Handling & Limitations
- **2GB Limit**: DETS has a hard 2GB file size limit. The error `FileSizeLimitExceeded` is defined in Gleam but not mapped in `dets_ffi.erl` (falls through to `ErlangError`).
- **ForceRepair Safety**: `ForceRepair` can silently overwrite/corrupt non-DETS files. Needs a warning or validation (`is_dets_file` check before open).
- **Error Leakage**: `ErlangError(String)` leaks raw internal error terms. Consider sanitizing for public consumption.

### 2. API & Documentation
- **`delete_object` Semantics**: The documentation incorrectly claims `delete_object` is equivalent to `delete_key` for sets. It is not; `delete_object` matches on `{Key, Value}`, so it acts as a "conditional delete" even for sets.
- **Missing Guides**: Add sections for:
    - **Concurrency**: How `with_table` interacts with processes (DETS ownership).
    - **Corruption**: How to use `RepairPolicy`.
    - **Performance**: Write-through behavior (no caching).

### 3. Testing
- **Coverage**: Add tests for `insert_list` duplicate handling (does last-write-win for sets?).
- **Concurrency**: Add a test for `update_counter` under concurrent load.
- **Non-ASCII Paths**: Verify `binary_to_atom` handles UTF-8 paths correctly without crashing.

---

## ℹ️ Nits

- **`internal_modules`**: `gleam.toml` has a commented-out reference to `dets/internal`. Update to `slate/internal`.
- **Target Visibility**: Explicitly state "Erlang Target Only" in the README header.
- **Test Helpers**: Deduplicate `cleanup` and `unsafe_decoder` in `test/` if possible.

---

## Action Plan

1.  **Fix README**: Update examples to compile.
2.  **Safety Warning**: Document the atom exhaustion risk.
3.  **Refactor**: Create `src/slate/internal.gleam` and extract shared logic.
4.  **Fix Doc Comments**: Correct `delete_object` documentation.
5.  **Enhance FFI**: Map `efbig` (2GB limit) to `FileSizeLimitExceeded`.
