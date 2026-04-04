# dotes

A simple note-taking CLI built with [slate](https://github.com/tylerbutler/slate) — demonstrates the full slate API across all three table types.

## Running

From this directory:

```sh
gleam run -- <command>
```

## Commands

```sh
# Create a new note
gleam run -- save "Shopping List" "Milk, eggs, bread"

# Edit an existing note (archives the old body in history)
gleam run -- save 1 "Milk, eggs, bread, butter"

# List all notes
gleam run -- show

# Show a single note with tags and edit history
gleam run -- show 1

# Toggle a tag (adds if missing, removes if present)
gleam run -- tag 1 "groceries"

# Delete a note and all its tags/history
gleam run -- delete 1
```

## How it uses slate

dotes uses **four DETS tables**, one for each slate table type:

| Table | Type | Key → Value | Purpose |
|-------|------|-------------|---------|
| `counter.dets` | `Set(String, Int)` | `"next_id"` → `Int` | Auto-incrementing IDs via `update_counter` |
| `notes.dets` | `Set(Int, Note)` | note ID → `Note` | Primary note storage |
| `tags.dets` | `Bag(Int, String)` | note ID → tag strings | Multiple distinct tags per note |
| `history.dets` | `DuplicateBag(Int, Revision)` | note ID → revisions | Edit history that accumulates over time |

### slate API coverage

| Command | API functions used |
|---------|-------------------|
| `save` (new) | `set.insert_new`, `set.update_counter` |
| `save` (edit) | `set.lookup`, `set.insert`, `duplicate_bag.insert` |
| `show` (list) | `set.fold` |
| `show` (one) | `set.lookup`, `bag.lookup`, `duplicate_bag.lookup` |
| `tag` | `set.lookup`, `bag.lookup`, `bag.insert`, `bag.delete_object` |
| `delete` | `set.lookup`, `set.delete_key`, `bag.delete_key`, `duplicate_bag.delete_key` |

Data is stored in a `.dotes/` directory in the current working directory.
