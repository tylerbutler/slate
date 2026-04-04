import argv
import dotes/store
import dotes/types.{type Revision}
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import slate

pub fn main() {
  case argv.load().arguments {
    ["save", first, second] -> cmd_save(first, second)
    ["show"] -> cmd_list()
    ["show", id_str] -> cmd_show(id_str)
    ["tag", id_str, tag] -> cmd_tag(id_str, tag)
    ["delete", id_str] -> cmd_delete(id_str)
    _ -> print_usage()
  }
}

/// Run a function with an open store, closing it afterward.
fn with_store(f: fn(store.Store) -> Nil) -> Nil {
  case store.open() {
    Ok(s) -> {
      f(s)
      case store.close(s) {
        Ok(Nil) -> Nil
        Error(e) ->
          io.println("Error closing store: " <> slate.error_message(e))
      }
    }
    Error(e) -> io.println("Error opening store: " <> slate.error_message(e))
  }
}

/// Parse a note ID from a string, printing an error and calling f on success.
fn with_id(id_str: String, f: fn(Int) -> Nil) -> Nil {
  case int.parse(id_str) {
    Error(_) -> io.println("Error: '" <> id_str <> "' is not a valid note ID")
    Ok(id) -> f(id)
  }
}

fn cmd_save(first: String, second: String) -> Nil {
  case int.parse(first) {
    Ok(id) ->
      with_store(fn(s) {
        case store.update_note(s, id: id, body: second) {
          Ok(Nil) -> io.println("✓ Updated note #" <> int.to_string(id))
          Error(e) -> io.println("Error: " <> slate.error_message(e))
        }
      })
    Error(_) ->
      with_store(fn(s) {
        case store.create_note(s, title: first, body: second) {
          Ok(id) -> io.println("✓ Created note #" <> int.to_string(id))
          Error(e) -> io.println("Error: " <> slate.error_message(e))
        }
      })
  }
}

fn cmd_list() -> Nil {
  with_store(fn(s) {
    case store.list_notes(s) {
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
            <> types.format_timestamp(note.created_at)
            <> ")",
          )
        })
      }
      Error(e) -> io.println("Error: " <> slate.error_message(e))
    }
  })
}

fn cmd_show(id_str: String) -> Nil {
  with_id(id_str, fn(id) {
    with_store(fn(s) {
      case store.get_note(s, id) {
        Error(e) -> io.println("Error: " <> slate.error_message(e))
        Ok(note) -> {
          io.println("Note #" <> int.to_string(id))
          io.println("Title:   " <> note.title)
          io.println("Body:    " <> note.body)
          io.println("Created: " <> types.format_timestamp(note.created_at))

          case store.get_tags(s, id) {
            Ok([]) -> Nil
            Ok(tags) -> io.println("Tags:    " <> string.join(tags, ", "))
            Error(_) -> Nil
          }

          case store.get_history(s, id) {
            Ok([]) -> Nil
            Ok(revisions) -> {
              io.println(
                "\nHistory ("
                <> int.to_string(list.length(revisions))
                <> " revisions):",
              )
              list.each(revisions, fn(rev: Revision) {
                io.println(
                  "  ["
                  <> types.format_timestamp(rev.edited_at)
                  <> "] "
                  <> rev.body,
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

fn cmd_tag(id_str: String, tag: String) -> Nil {
  with_id(id_str, fn(id) {
    with_store(fn(s) {
      case store.toggle_tag(s, id: id, tag: tag) {
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

fn cmd_delete(id_str: String) -> Nil {
  with_id(id_str, fn(id) {
    with_store(fn(s) {
      case store.delete_note(s, id) {
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
