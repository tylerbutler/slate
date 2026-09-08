import argv
import dotes/store.{type Revision}
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import slate

pub fn main() -> Nil {
  case argv.load().arguments {
    ["save", first, second] -> command_save(first, second)
    ["show"] -> command_list()
    ["show", id_string] -> command_show(id_string)
    ["tag", id_string, tag] -> command_tag(id_string, tag)
    ["delete", id_string] -> command_delete(id_string)
    _ -> print_usage()
  }
}

/// Run a function with an open store, closing it afterward.
fn with_store(f: fn(store.Store) -> Nil) -> Nil {
  case store.open() {
    Ok(store) -> {
      f(store)
      case store.close(store) {
        Ok(Nil) -> Nil
        Error(e) ->
          io.println("Error closing store: " <> slate.error_message(e))
      }
    }
    Error(e) -> io.println("Error opening store: " <> slate.error_message(e))
  }
}

/// Parse a note ID from a string, printing an error and calling f on success.
fn with_id(id_string: String, f: fn(Int) -> Nil) -> Nil {
  case int.parse(id_string) {
    Error(_) ->
      io.println("Error: '" <> id_string <> "' is not a valid note ID")
    Ok(id) -> f(id)
  }
}

fn command_save(first: String, second: String) -> Nil {
  case int.parse(first) {
    Ok(id) ->
      with_store(fn(store) {
        case store.update_note(store, id: id, body: second) {
          Ok(Nil) -> io.println("✓ Updated note #" <> int.to_string(id))
          Error(e) -> io.println("Error: " <> slate.error_message(e))
        }
      })
    Error(_) ->
      with_store(fn(store) {
        case store.create_note(store, title: first, body: second) {
          Ok(id) -> io.println("✓ Created note #" <> int.to_string(id))
          Error(e) -> io.println("Error: " <> slate.error_message(e))
        }
      })
  }
}

fn command_list() -> Nil {
  with_store(fn(store) {
    case store.list_notes(store) {
      Ok([]) ->
        io.println(
          "No notes yet. Create one with: dotes save \"Title\" \"Body\"",
        )
      Ok(notes) -> {
        io.println("Notes:")
        list.each(notes, fn(pair) {
          let #(id, note) = pair
          io.println(
            "  #"
            <> int.to_string(id)
            <> "  "
            <> note.title
            <> "  ("
            <> store.unix_seconds_to_rfc3339(note.created_at)
            <> ")",
          )
        })
      }
      Error(e) -> io.println("Error: " <> slate.error_message(e))
    }
  })
}

fn command_show(id_string: String) -> Nil {
  with_id(id_string, fn(id) {
    with_store(fn(store) {
      case store.get_note(store, id) {
        Error(e) -> io.println("Error: " <> slate.error_message(e))
        Ok(note) -> {
          io.println("Note #" <> int.to_string(id))
          io.println("Title:   " <> note.title)
          io.println("Body:    " <> note.body)
          io.println(
            "Created: " <> store.unix_seconds_to_rfc3339(note.created_at),
          )

          // Tags and history are optional display sections — if the
          // lookups fail, omit the section rather than blocking the note.
          case store.get_tags(store, id) {
            Ok([]) -> Nil
            Ok(tags) -> io.println("Tags:    " <> string.join(tags, ", "))
            Error(_) -> Nil
          }

          case store.get_history(store, id) {
            Ok([]) -> Nil
            Ok(revisions) -> {
              io.println(
                "\nHistory ("
                <> int.to_string(list.length(revisions))
                <> " revisions):",
              )
              list.each(revisions, fn(revision: Revision) {
                io.println(
                  "  ["
                  <> store.unix_seconds_to_rfc3339(revision.edited_at)
                  <> "] "
                  <> revision.body,
                )
              })
            }
            Error(_) -> Nil
          }
        }
      }
    })
  })
}

fn command_tag(id_string: String, tag: String) -> Nil {
  with_id(id_string, fn(id) {
    with_store(fn(store) {
      case store.toggle_tag(store, id: id, tag: tag) {
        Ok(True) ->
          io.println(
            "✓ Added tag '" <> tag <> "' to note #" <> int.to_string(id),
          )
        Ok(False) ->
          io.println(
            "✓ Removed tag '" <> tag <> "' from note #" <> int.to_string(id),
          )
        Error(e) -> io.println("Error: " <> slate.error_message(e))
      }
    })
  })
}

fn command_delete(id_string: String) -> Nil {
  with_id(id_string, fn(id) {
    with_store(fn(store) {
      case store.delete_note(store, id) {
        Ok(Nil) -> io.println("✓ Deleted note #" <> int.to_string(id))
        Error(e) -> io.println("Error: " <> slate.error_message(e))
      }
    })
  })
}

fn print_usage() -> Nil {
  io.println("dotes — a simple note-taking CLI powered by slate")
  io.println("")
  io.println("Usage:")
  io.println("  dotes save \"Title\" \"Body\"    Create a new note")
  io.println("  dotes save <id> \"New body\"   Edit an existing note")
  io.println("  dotes show                    List all notes")
  io.println(
    "  dotes show <id>               Show a note with tags and history",
  )
  io.println("  dotes tag <id> \"tag\"          Toggle a tag on a note")
  io.println("  dotes delete <id>             Delete a note and its data")
}
