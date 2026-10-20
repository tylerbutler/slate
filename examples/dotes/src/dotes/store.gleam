import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import simplifile
import slate
import slate/bag
import slate/duplicate_bag
import slate/exclusive
import slate/set

/// A note with a title, body, and creation timestamp (Unix seconds).
pub type Note {
  Note(title: String, body: String, created_at: Int)
}

/// A historical revision of a note's body.
pub type Revision {
  Revision(body: String, edited_at: Int)
}

/// A readable note and independent outcomes for its supplementary sections.
pub type Detail {
  Detail(
    note: Note,
    tags: Result(List(String), Error),
    history: Result(List(Revision), Error),
  )
}

/// Decoder for Note values stored as {note, Title, Body, CreatedAt}.
fn note_decoder() -> decode.Decoder(Note) {
  use title <- decode.field(1, decode.string)
  use body <- decode.field(2, decode.string)
  use created_at <- decode.field(3, decode.int)
  decode.success(Note(title:, body:, created_at:))
}

/// Decoder for Revision values stored as {revision, Body, EditedAt}.
fn revision_decoder() -> decode.Decoder(Revision) {
  use body <- decode.field(1, decode.string)
  use edited_at <- decode.field(2, decode.int)
  decode.success(Revision(body:, edited_at:))
}

/// Convert Unix seconds to an RFC 3339 UTC string.
pub fn unix_seconds_to_rfc3339(seconds: Int) -> String {
  timestamp.from_unix_seconds(seconds)
  |> timestamp.to_rfc3339(calendar.utc_offset)
}

fn now() -> Int {
  let #(seconds, _nanoseconds) =
    timestamp.system_time()
    |> timestamp.to_unix_seconds_and_nanoseconds()
  seconds
}

/// A client of one store owner. The process that calls open owns its lifetime.
/// Clients may share this handle, but never the scoped DETS handles.
pub opaque type Store {
  Store(owner: process.Pid, requests: Subject(Request))
}

/// The table involved in a session failure.
pub type Table {
  Counter
  Notes
  Tags
  History
}

/// One complete session error, including its primary and cleanup failures.
pub type SessionIssue {
  SessionIssue(table: Table, error: exclusive.SessionError)
}

/// Store operations are not transactions. A failure may follow earlier writes.
/// OwnerStopped means the outcome of an outstanding write may be unknown:
/// callers must not automatically retry it.
pub type Error {
  Storage(slate.DetsError)
  Directory(simplifile.FileError)
  Sessions(List(SessionIssue))
  OwnerStopped(process.ExitReason)
}

/// Safe for terminal/browser display: never includes paths or native details.
pub fn error_message(error: Error) -> String {
  case error {
    Storage(error) -> slate.error_message(error)
    Directory(_) -> "Cannot create the dotes data directory."
    OwnerStopped(_) ->
      "The dotes store stopped. An outstanding write may not have completed."
    Sessions(issues) ->
      issues
      |> list.map(fn(issue) {
        table_name(issue.table) <> ": " <> session_message(issue.error)
      })
      |> string.join(" ")
  }
}

fn session_message(error: exclusive.SessionError) -> String {
  case error {
    exclusive.AcquisitionFailed(exclusive.Busy) ->
      "The dotes store is in use. Close the other dotes CLI, TUI, or web app first."
    exclusive.CleanupFailed(primary, failures) -> {
      let primary_message = case primary {
        None -> ""
        Some(failure) ->
          exclusive.error_message(exclusive.SessionFailed(failure)) <> " "
      }
      let cleanup_messages =
        list.map(failures, fn(failure) {
          case failure {
            exclusive.CloseFailure(error) ->
              "Close failed: " <> slate.error_message(error)
            exclusive.ReleaseFailure(error) ->
              "Lock release failed: "
              <> exclusive.error_message(exclusive.AcquisitionFailed(error))
            exclusive.GuardianStopped(_) -> "The session guardian stopped."
          }
        })
        |> string.join(" ")
      primary_message
      <> exclusive.error_message(error)
      <> " "
      <> cleanup_messages
    }
    _ -> exclusive.error_message(error)
  }
}

fn table_name(table: Table) -> String {
  case table {
    Counter -> "counter"
    Notes -> "notes"
    Tags -> "tags"
    History -> "history"
  }
}

// Only constructed and used inside the four live exclusive callbacks.
type Tables {
  Tables(
    counter: set.Set(String, Int),
    notes: set.Set(Int, Note),
    tags: bag.Bag(Int, String),
    history: duplicate_bag.DuplicateBag(Int, Revision),
  )
}

type Request {
  Run(fn(Tables) -> Nil)
  Stop(Subject(Result(Nil, Error)))
}

type OwnerMessage {
  Request(Request)
  ParentStopped
}

/// Open the default .dotes directory. No unlocked or native-free fallback.
pub fn open() -> Result(Store, Error) {
  open_in(".dotes")
}

/// Open an isolated directory without changing the VM's working directory.
/// Acquires counter -> notes -> tags -> history, failing immediately if busy.
/// Success is acknowledged only once every exclusive callback is active.
pub fn open_in(directory: String) -> Result(Store, Error) {
  use _ <- result.try(
    simplifile.create_directory_all(directory) |> result.map_error(Directory),
  )
  let parent = process.self()
  let started = process.new_subject()
  let owner = process.spawn_unlinked(fn() { own(directory, parent, started) })
  await(process.monitor(owner), started)
}

/// Stop accepting requests and unwind every session before replying.
/// Cleanup failure can quarantine ownership until VM exit; never force unlock.
/// Closing a dead/already closed owner returns OwnerStopped, not success.
pub fn close(store: Store) -> Result(Nil, Error) {
  let reply = process.new_subject()
  let monitor = process.monitor(store.owner)
  process.send(store.requests, Stop(reply))
  await(monitor, reply)
}

// Monitor only for the duration of a call, selecting the exact reply and DOWN.
// No arbitrary timeout: it could abandon a write or leave a late reply behind.
// Native/session operations have their own failure and quarantine guarantees.
fn await(
  monitor: process.Monitor,
  reply: Subject(Result(a, Error)),
) -> Result(a, Error) {
  let response =
    process.new_selector()
    |> process.select(reply)
    |> process.select_specific_monitor(monitor, fn(down) {
      Error(OwnerStopped(down.reason))
    })
    |> process.selector_receive_forever
  process.demonitor_process(monitor)
  response
}

fn own(
  directory: String,
  parent: process.Pid,
  started: Subject(Result(Store, Error)),
) -> Nil {
  let parent_monitor = process.monitor(parent)
  let requests = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select_map(requests, Request)
    |> process.select_specific_monitor(parent_monitor, fn(_) { ParentStopped })
  // A local journal is essential: an outer CleanupFailed discards its
  // callback's successful value, which might itself contain an inner failure.
  // Record each complete session result after it returns, never raw handles.
  let issues = process.new_subject()
  let stopped = process.new_subject()
  {
    use <- record_session(issues, Counter)
    use counter <- set.with_exclusive_table(
      directory <> "/counter.dets",
      slate.AutoRepair,
      slate.ReadWrite,
      exclusive.Immediate,
      decode.string,
      decode.int,
    )
    {
      use <- record_session(issues, Notes)
      use notes <- set.with_exclusive_table(
        directory <> "/notes.dets",
        slate.AutoRepair,
        slate.ReadWrite,
        exclusive.Immediate,
        decode.int,
        note_decoder(),
      )
      {
        use <- record_session(issues, Tags)
        use tags <- bag.with_exclusive_table(
          directory <> "/tags.dets",
          slate.AutoRepair,
          slate.ReadWrite,
          exclusive.Immediate,
          decode.int,
          decode.string,
        )
        {
          use <- record_session(issues, History)
          use history <- duplicate_bag.with_exclusive_table(
            directory <> "/history.dets",
            slate.AutoRepair,
            slate.ReadWrite,
            exclusive.Immediate,
            decode.int,
            revision_decoder(),
          )
          process.send(started, Ok(Store(process.self(), requests)))
          let reply = loop(Tables(counter:, notes:, tags:, history:), selector)
          process.send(stopped, reply)
          Ok(Nil)
        }
        Ok(Nil)
      }
      Ok(Nil)
    }
    Ok(Nil)
  }
  process.demonitor_process(parent_monitor)
  let outcome = case collect_issues(issues, []) {
    [] -> Ok(Nil)
    errors -> Error(Sessions(errors))
  }
  // A Stop reply may belong to a parent that died during unwind. Log cleanup
  // failures independently of reply delivery; checking liveness would race.
  // Duplicate reporting to a surviving caller is preferable to silent loss.
  case outcome {
    Error(Sessions(issues) as error) ->
      case
        list.any(issues, fn(issue) {
          case issue.error {
            exclusive.CleanupFailed(..) -> True
            _ -> False
          }
        })
      {
        True -> io.println("Error closing store: " <> error_message(error))
        False -> Nil
      }
    _ -> Nil
  }
  case process.receive(stopped, 0) {
    // No callback reached the loop: opening failed. All earlier scopes have
    // now unwound, including any cleanup failures recorded in the journal.
    Error(Nil) ->
      process.send(
        started,
        result.map(outcome, fn(_) {
          // Unreachable: without reaching the innermost callback a session failed.
          panic as "Store sessions ended without starting or failing"
        }),
      )
    Ok(Some(reply)) -> process.send(reply, outcome)
    Ok(None) -> Nil
  }
}

fn record_session(
  issues: Subject(SessionIssue),
  table: Table,
  run: fn() -> Result(Nil, exclusive.SessionError),
) -> Nil {
  case run() {
    Ok(Nil) -> Nil
    Error(error) -> process.send(issues, SessionIssue(table, error))
  }
}

fn collect_issues(
  issues: Subject(SessionIssue),
  acc: List(SessionIssue),
) -> List(SessionIssue) {
  case process.receive(issues, 0) {
    Ok(issue) -> collect_issues(issues, [issue, ..acc])
    Error(Nil) -> list.reverse(acc)
  }
}

fn loop(
  tables: Tables,
  selector: process.Selector(OwnerMessage),
) -> Option(Subject(Result(Nil, Error))) {
  case process.selector_receive_forever(selector) {
    ParentStopped -> None
    Request(Stop(reply)) -> Some(reply)
    Request(Run(run)) -> {
      run(tables)
      loop(tables, selector)
    }
  }
}

fn call(
  store: Store,
  operation: fn(Tables) -> Result(a, slate.DetsError),
) -> Result(a, Error) {
  let reply = process.new_subject()
  let monitor = process.monitor(store.owner)
  process.send(
    store.requests,
    Run(fn(tables) {
      process.send(reply, operation(tables) |> result.map_error(Storage))
    }),
  )
  await(monitor, reply)
}

/// Generate the next note ID using an atomic counter.
fn next_id(store: Tables) -> Result(Int, slate.DetsError) {
  // update_counter requires the key to already exist. insert_new is a no-op
  // if the key is already present, so this safely seeds the counter only once.
  use _ <- result.try(case set.insert_new(store.counter, "next_id", 0) {
    Ok(Nil) | Error(slate.KeyAlreadyPresent) -> Ok(Nil)
    Error(error) -> Error(error)
  })
  case set.update_counter(store.counter, "next_id", 1) {
    Ok(id) -> Ok(id)
    Error(set.TableError(error)) -> Error(error)
    Error(set.CounterValueNotInteger) ->
      Error(slate.UnexpectedError("Counter value is not an integer"))
  }
}

/// Create a new note. Returns the assigned ID.
pub fn create_note(
  store: Store,
  title title: String,
  body body: String,
) -> Result(Int, Error) {
  use store <- call(store)
  use id <- result.try(next_id(store))
  let note = Note(title:, body:, created_at: now())
  use _ <- result.try(set.insert_new(store.notes, id, note))
  Ok(id)
}

/// Update an existing note's body, archiving the previous version.
pub fn update_note(
  store: Store,
  id id: Int,
  body body: String,
) -> Result(Nil, Error) {
  use store <- call(store)
  use current <- result.try(set.lookup(store.notes, key: id))
  let revision = Revision(body: current.body, edited_at: now())
  use _ <- result.try(duplicate_bag.insert(store.history, id, revision))
  let updated = Note(..current, body:)
  set.insert(store.notes, id, updated)
}

/// Look up a single note by ID.
pub fn get_note(store: Store, id: Int) -> Result(Note, Error) {
  use store <- call(store)
  set.lookup(store.notes, key: id)
}

/// Read one detail snapshot in the owner. A missing note remains the primary
/// error; failed supplementary reads do not hide a readable note.
pub fn get_detail(store: Store, id: Int) -> Result(Detail, Error) {
  use store <- call(store)
  use note <- result.try(set.lookup(store.notes, key: id))
  let tags = bag.lookup(store.tags, key: id) |> result.map_error(Storage)
  let history =
    duplicate_bag.lookup(store.history, key: id) |> result.map_error(Storage)
  Ok(Detail(note:, tags:, history:))
}

/// List all notes as (id, note) pairs, sorted by ID.
pub fn list_notes(store: Store) -> Result(List(#(Int, Note)), Error) {
  use store <- call(store)
  use notes <- result.try(
    set.fold(store.notes, [], fn(acc, id, note) { [#(id, note), ..acc] }),
  )
  Ok(
    list.sort(notes, by: fn(a, b) {
      let #(id_a, _) = a
      let #(id_b, _) = b
      int.compare(id_a, id_b)
    }),
  )
}

/// Get all tags for a note.
pub fn get_tags(store: Store, id: Int) -> Result(List(String), Error) {
  use store <- call(store)
  bag.lookup(store.tags, key: id)
}

/// Get edit history for a note.
pub fn get_history(store: Store, id: Int) -> Result(List(Revision), Error) {
  use store <- call(store)
  duplicate_bag.lookup(store.history, key: id)
}

/// Toggle a tag on a note. Returns True if added, False if removed.
pub fn toggle_tag(
  store: Store,
  id id: Int,
  tag tag: String,
) -> Result(Bool, Error) {
  use store <- call(store)
  // DETS delete is a no-op on missing keys; lookup first so we return
  // NotFound rather than silently succeeding on a ghost note.
  use _ <- result.try(set.lookup(store.notes, key: id))
  use current_tags <- result.try(bag.lookup(store.tags, key: id))
  case list.contains(current_tags, tag) {
    True -> {
      use _ <- result.try(bag.delete_object(store.tags, id, tag))
      Ok(False)
    }
    False -> {
      use _ <- result.try(bag.insert(store.tags, id, tag))
      Ok(True)
    }
  }
}

/// Delete a note and all its associated tags and history.
pub fn delete_note(store: Store, id: Int) -> Result(Nil, Error) {
  use store <- call(store)
  // DETS delete_key is a no-op when the key is absent, so lookup first to
  // return NotFound for a missing note rather than reporting success.
  use _ <- result.try(set.lookup(store.notes, key: id))
  use _ <- result.try(bag.delete_key(store.tags, id))
  use _ <- result.try(duplicate_bag.delete_key(store.history, id))
  set.delete_key(store.notes, id)
}
