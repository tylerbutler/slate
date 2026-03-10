# Changelog


## v0.1.0 - 2026-03-10


#### Added

##### Initial release of slate, a type-safe Gleam wrapper for Erlang DETS.

- Set tables with unique keys and insert/lookup/delete operations
- Bag tables supporting multiple distinct values per key
- Duplicate bag tables allowing duplicate key-value pairs
- Safe resource management with `with_table` helper
- Comprehensive error handling via Gleam Result types
- Configurable repair policies (auto, force, none)


