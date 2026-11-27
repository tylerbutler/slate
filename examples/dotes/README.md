# dotes

A simple note-taking CLI built with [slate](https://github.com/tylerbutler/slate) — demonstrates the full slate API across all three table types.

## Running

Install the pinned tools, including Rebar3 for the Erlang HTTP dependencies,
then build Slate's native lock component from the repository root:

```sh
mise install
just native-build
cd examples/dotes
```

Run the commands below from `examples/dotes`. Dotes opens every table in an
exclusive session, so it requires the native component and a qualified local
filesystem. If either is unavailable, startup reports an error rather than
opening the files without locks.

### Interactive TUI

Launch the interactive terminal UI:

```sh
gleam run -m dotes/tui
```

> **Note:** The TUI requires Erlang/OTP 28+ (via [Shore](https://hex.pm/packages/shore)).

Navigate with arrow keys, press `n` to create notes, `Enter` to view details,
`e` to edit, `d` to delete, and `Ctrl+X` to exit.

### Web App

Launch the web interface:

```sh
gleam run -m dotes/web
```

Then open [http://localhost:3000](http://localhost:3000) in your browser. Uses
[Lustre](https://hex.pm/packages/lustre) server components — the app runs on the
server with full DETS access and sends DOM patches to the browser over WebSocket.

### CLI

From this directory:

```sh
gleam run -- <command>
```

## CLI Commands

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

A note needs four kinds of data, and each kind fits a different table type.
dotes uses **four DETS tables**:

| Table | Type | Key → Value | Purpose |
|-------|------|-------------|---------|
| `counter.dets` | `Set(String, Int)` | `"next_id"` → `Int` | Auto-incrementing IDs via `update_counter` |
| `notes.dets` | `Set(Int, Note)` | note ID → `Note` | Primary note storage |
| `tags.dets` | `Bag(Int, String)` | note ID → tag strings | Multiple distinct tags per note |
| `history.dets` | `DuplicateBag(Int, Revision)` | note ID → revisions | Edit history that accumulates over time |

Follow one note through its life to see how the tables work together. `save`
takes a new ID from the counter and stores the body under it. A second `save`
moves the old body into the history and stores the new one. `tag` adds or
removes one tag in the bag. `delete` removes the note's tags and history, then
the note itself.

### slate API coverage

Each command uses only the functions that its step needs:

| Command | API functions used |
|---------|-------------------|
| `save` (new) | `set.insert_new`, `set.update_counter` |
| `save` (edit) | `set.lookup`, `set.insert`, `duplicate_bag.insert` |
| `show` (list) | `set.fold` |
| `show` (one) | `set.lookup`, `bag.lookup`, `duplicate_bag.lookup` |
| `tag` | `set.lookup`, `bag.lookup`, `bag.insert`, `bag.delete_object` |
| `delete` | `set.lookup`, `set.delete_key`, `bag.delete_key`, `duplicate_bag.delete_key` |

Data is stored in a `.dotes/` directory in the current working directory.

### Ownership and failure handling

Four tables mean four files that must stay consistent with each other, so
dotes lets only one process change them. One dotes process owns a data
directory at a time. While the web app or TUI is
running, another CLI, TUI, or web process reports that the store is in use.
Close the running app before switching interfaces. Multiple browser clients
can use the same web process.

The store owner acquires exclusive sessions for all four tables and serializes
complete note operations. Concurrent edits retain each acknowledged body in the
current note or its history. Deletion removes tags and history before the note,
so a failed dependent deletion leaves the note available for a retry.

Startup unwinds earlier sessions if a later table cannot open. Shutdown attempts
cleanup for every session and reports failures. A cleanup failure can retain
ownership until the VM exits. Do not delete or replace `.slate.lock` sidecars
while a process can access the store.

These operations do not provide transactions or rollback. A failed operation
can have written some data; a process failure does not prove that a write failed.
Do not automatically repeat a write after an unknown outcome. Abrupt VM
termination can still leave files needing repair.

If tags or history cannot load, the interfaces keep readable note content and
successful sections visible and show an error for each failed section.

## Tests

Run `gleam test` from this directory after the native build. Tests use Unitest,
as the Slate library does. Keep the default sequential execution.
They cover independent-VM contention, concurrent mutations, failed startup and
cleanup, asynchronous results, and real loopback WebSocket connections.
Tests use isolated directories under `build/` and remove data and sidecars only
after the owning processes have stopped.

The tests also check how the interfaces handle work that arrives late or
fails. A late operation result cannot replace a newer draft, request, or
screen, including a later visit to the same note. The web server returns
HTTP 500 if the Lustre runtime is unavailable. If a WebSocket component cannot
start, it logs the failure and closes the connection. A failed frame send
stops the WebSocket and shuts down its component.
