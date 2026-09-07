import dotes/store.{type Note, type Revision, type Store}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import shore
import shore/key
import shore/layout
import shore/style
import shore/ui
import slate

// --- Types ---

/// The screen currently shown in the terminal.
pub type Screen {
  NoteList
  NoteDetail(id: Int)
  NoteCreate
  NoteEdit(id: Int)
  ConfirmDelete(id: Int)
}

/// Terminal state, separate from commands so updates can be tested directly.
pub type Model {
  Model(
    store: Store,
    screen: Screen,
    notes: List(#(Int, Note)),
    selected_index: Int,
    detail_note: Result(Note, Nil),
    detail_tags: List(String),
    detail_history: List(Revision),
    title_input: String,
    body_input: String,
    tag_input: String,
    status_message: String,
    status_is_error: Bool,
  )
}

/// Input events and note-specific command results.
pub type Message {
  // Async results
  NotesLoaded(Result(List(#(Int, Note)), String))
  NoteDetailLoaded(Int, Result(#(Note, List(String), List(Revision)), String))
  NoteCreated(Result(Int, String))
  NoteUpdated(Int, Result(Nil, String))
  NoteDeleted(Result(Nil, String))
  TagToggled(Int, Result(Bool, String))
  // Navigation
  GoToList
  GoToCreate
  GoToDetail(Int)
  GoToEdit(Int)
  AskDelete(Int)
  CancelDelete
  // List cursor
  SelectUp
  SelectDown
  // Form input
  TitleChanged(String)
  BodyChanged(String)
  TagChanged(String)
  // Actions
  SubmitCreate
  SubmitEdit(Int)
  SubmitToggleTag(Int)
  ConfirmDeleteNote(Int)
}

// --- Main ---

pub fn main() -> Nil {
  let assert Ok(store) = store.open()
  let exit = process.new_subject()
  let assert Ok(_actor) =
    shore.spec(
      init: fn() { init(store) },
      view: view,
      update: update,
      exit: exit,
      keybinds: shore.default_keybinds(),
      redraw: shore.on_timer(100),
    )
    |> shore.start
  exit |> process.receive_forever
  let _ = store.close(store)
  Nil
}

// --- Init ---

/// Create the terminal state and its initial load command.
pub fn init(store: Store) -> #(Model, List(fn() -> Message)) {
  let model =
    Model(
      store: store,
      screen: NoteList,
      notes: [],
      selected_index: 0,
      detail_note: Error(Nil),
      detail_tags: [],
      detail_history: [],
      title_input: "",
      body_input: "",
      tag_input: "",
      status_message: "",
      status_is_error: False,
    )
  #(model, [load_notes_command(store)])
}

// --- Commands ---

fn load_notes_command(store: Store) -> fn() -> Message {
  fn() {
    case store.list_notes(store) {
      Ok(notes) -> NotesLoaded(Ok(notes))
      Error(e) -> NotesLoaded(Error(slate.error_message(e)))
    }
  }
}

fn load_detail_command(store: Store, id: Int) -> fn() -> Message {
  fn() {
    case store.get_note(store, id) {
      Error(e) -> NoteDetailLoaded(id, Error(slate.error_message(e)))
      Ok(note) -> {
        let tags = store.get_tags(store, id) |> result.unwrap([])
        let history = store.get_history(store, id) |> result.unwrap([])
        NoteDetailLoaded(id, Ok(#(note, tags, history)))
      }
    }
  }
}

fn create_note_command(
  store: Store,
  title: String,
  body: String,
) -> fn() -> Message {
  fn() {
    case store.create_note(store, title: title, body: body) {
      Ok(id) -> NoteCreated(Ok(id))
      Error(e) -> NoteCreated(Error(slate.error_message(e)))
    }
  }
}

fn update_note_command(store: Store, id: Int, body: String) -> fn() -> Message {
  fn() {
    case store.update_note(store, id: id, body: body) {
      Ok(Nil) -> NoteUpdated(id, Ok(Nil))
      Error(e) -> NoteUpdated(id, Error(slate.error_message(e)))
    }
  }
}

fn toggle_tag_command(store: Store, id: Int, tag: String) -> fn() -> Message {
  fn() {
    case store.toggle_tag(store, id: id, tag: tag) {
      Ok(added) -> TagToggled(id, Ok(added))
      Error(e) -> TagToggled(id, Error(slate.error_message(e)))
    }
  }
}

fn delete_note_command(store: Store, id: Int) -> fn() -> Message {
  fn() {
    case store.delete_note(store, id) {
      Ok(Nil) -> NoteDeleted(Ok(Nil))
      Error(e) -> NoteDeleted(Error(slate.error_message(e)))
    }
  }
}

// --- Update ---

/// Apply an event without running its returned commands.
pub fn update(
  model: Model,
  message: Message,
) -> #(Model, List(fn() -> Message)) {
  case message {
    // Data loaded
    NotesLoaded(Ok(notes)) -> {
      let index = clamp_index(model.selected_index, notes)
      #(Model(..model, notes: notes, selected_index: index), [])
    }
    NotesLoaded(Error(e)) -> #(
      Model(..model, status_message: e, status_is_error: True),
      [],
    )

    NoteDetailLoaded(id, result) ->
      case model.screen {
        NoteDetail(current_id) if current_id == id ->
          case result {
            Ok(#(note, tags, history)) -> #(
              Model(
                ..model,
                detail_note: Ok(note),
                detail_tags: tags,
                detail_history: history,
              ),
              [],
            )
            Error(error) -> #(
              Model(
                ..model,
                status_message: error,
                status_is_error: True,
                screen: NoteList,
              ),
              [load_notes_command(model.store)],
            )
          }
        NoteList
        | NoteCreate
        | NoteEdit(_)
        | ConfirmDelete(_)
        | NoteDetail(_) -> #(model, [])
      }

    // Navigation
    GoToList -> #(
      Model(
        ..model,
        screen: NoteList,
        title_input: "",
        body_input: "",
        tag_input: "",
        status_message: "",
      ),
      [load_notes_command(model.store)],
    )
    GoToCreate -> #(
      Model(
        ..model,
        screen: NoteCreate,
        title_input: "",
        body_input: "",
        status_message: "",
      ),
      [],
    )
    GoToDetail(id) -> #(
      Model(
        ..model,
        screen: NoteDetail(id),
        detail_note: Error(Nil),
        detail_tags: [],
        detail_history: [],
        tag_input: "",
        status_message: "",
      ),
      [load_detail_command(model.store, id)],
    )
    GoToEdit(id) -> {
      let body = case model.detail_note {
        Ok(note) -> note.body
        Error(_) -> ""
      }
      #(
        Model(
          ..model,
          screen: NoteEdit(id),
          body_input: body,
          status_message: "",
        ),
        [],
      )
    }
    AskDelete(id) -> #(Model(..model, screen: ConfirmDelete(id)), [])
    CancelDelete -> #(Model(..model, screen: NoteList), [])

    // List cursor
    SelectUp -> #(
      Model(..model, selected_index: int.max(0, model.selected_index - 1)),
      [],
    )
    SelectDown -> {
      let max_index = int.max(0, list.length(model.notes) - 1)
      #(
        Model(
          ..model,
          selected_index: int.min(max_index, model.selected_index + 1),
        ),
        [],
      )
    }

    // Form input
    TitleChanged(value) -> #(Model(..model, title_input: value), [])
    BodyChanged(value) -> #(Model(..model, body_input: value), [])
    TagChanged(value) -> #(Model(..model, tag_input: value), [])

    // Actions
    SubmitCreate -> #(model, [
      create_note_command(model.store, model.title_input, model.body_input),
    ])
    SubmitEdit(id) -> #(model, [
      update_note_command(model.store, id, model.body_input),
    ])
    SubmitToggleTag(id) -> {
      case model.tag_input {
        "" -> #(model, [])
        tag -> #(model, [toggle_tag_command(model.store, id, tag)])
      }
    }
    ConfirmDeleteNote(id) -> #(model, [delete_note_command(model.store, id)])

    // Action results
    NoteCreated(Ok(id)) -> #(
      Model(
        ..model,
        screen: NoteList,
        title_input: "",
        body_input: "",
        status_message: "Created note #" <> int.to_string(id),
        status_is_error: False,
      ),
      [load_notes_command(model.store)],
    )
    NoteCreated(Error(e)) -> #(
      Model(..model, status_message: e, status_is_error: True),
      [],
    )

    NoteUpdated(id, result) ->
      case model.screen {
        NoteEdit(current_id) if current_id == id ->
          case result {
            Ok(Nil) -> #(
              Model(
                ..model,
                screen: NoteDetail(id),
                detail_note: Error(Nil),
                status_message: "Note updated",
                status_is_error: False,
              ),
              [load_detail_command(model.store, id)],
            )
            Error(error) -> #(
              Model(..model, status_message: error, status_is_error: True),
              [],
            )
          }
        NoteList
        | NoteCreate
        | NoteDetail(_)
        | ConfirmDelete(_)
        | NoteEdit(_) -> #(model, [])
      }

    NoteDeleted(Ok(Nil)) -> #(
      Model(
        ..model,
        screen: NoteList,
        selected_index: 0,
        status_message: "Note deleted",
        status_is_error: False,
      ),
      [load_notes_command(model.store)],
    )
    NoteDeleted(Error(e)) -> #(
      Model(..model, status_message: e, status_is_error: True),
      [],
    )

    TagToggled(id, result) ->
      case model.screen {
        NoteDetail(current_id) if current_id == id ->
          case result {
            Ok(added) -> {
              let message = case added {
                True -> "Tag added"
                False -> "Tag removed"
              }
              #(
                Model(
                  ..model,
                  tag_input: "",
                  status_message: message,
                  status_is_error: False,
                ),
                [load_detail_command(model.store, id)],
              )
            }
            Error(error) -> #(
              Model(..model, status_message: error, status_is_error: True),
              [],
            )
          }
        NoteList
        | NoteCreate
        | NoteEdit(_)
        | ConfirmDelete(_)
        | NoteDetail(_) -> #(model, [])
      }
  }
}

fn clamp_index(index: Int, notes: List(#(Int, Note))) -> Int {
  let max = int.max(0, list.length(notes) - 1)
  int.clamp(index, 0, max)
}

// --- View ---

fn view(model: Model) -> shore.Node(Message) {
  case model.screen {
    NoteList -> view_list(model)
    NoteDetail(id) -> view_detail(model, id)
    NoteCreate -> view_create(model)
    NoteEdit(id) -> view_edit(model, id)
    ConfirmDelete(id) -> view_confirm_delete(model, id)
  }
}

fn view_list(model: Model) -> shore.Node(Message) {
  let content = case model.notes {
    [] -> [ui.text("No notes yet. Press [n] to create one.")]
    notes ->
      list.index_map(notes, fn(pair, index) {
        let #(id, note) = pair
        let prefix = case index == model.selected_index {
          True -> " > "
          False -> "   "
        }
        let line =
          prefix
          <> "#"
          <> int.to_string(id)
          <> "  "
          <> note.title
          <> "  ("
          <> store.unix_seconds_to_rfc3339(note.created_at)
          <> ")"
        case index == model.selected_index {
          True -> ui.text_styled(line, Some(style.Cyan), None)
          False -> ui.text(line)
        }
      })
  }

  let selected_id = get_selected_id(model)

  let action_buttons = case selected_id {
    Ok(id) ->
      ui.row([
        ui.button("n new", key.Char("n"), GoToCreate),
        ui.button("enter open", key.Enter, GoToDetail(id)),
        ui.button("d delete", key.Char("d"), AskDelete(id)),
      ])
    Error(_) -> ui.row([ui.button("n new", key.Char("n"), GoToCreate)])
  }

  let children =
    list.flatten([
      content,
      [ui.hr(), action_buttons, view_exit_hint(), view_status(model)],
      [ui.keybind(key.Up, SelectUp), ui.keybind(key.Down, SelectDown)],
    ])

  ui.box(children, Some("dotes"))
  |> layout.center(style.Px(60), style.Fill)
}

fn view_detail(model: Model, id: Int) -> shore.Node(Message) {
  let title = "note #" <> int.to_string(id)
  case model.detail_note {
    Error(_) ->
      ui.box(
        [ui.text("Loading..."), ui.keybind(key.Esc, GoToList)],
        Some(title),
      )
      |> layout.center(style.Px(60), style.Fill)
    Ok(note) -> {
      let tags_string = case model.detail_tags {
        [] -> "(none)"
        tags -> string.join(tags, ", ")
      }

      let info = [
        ui.table_kv(style.Px(56), [
          ["Title", note.title],
          ["Body", note.body],
          ["Created", store.unix_seconds_to_rfc3339(note.created_at)],
          ["Tags", tags_string],
        ]),
      ]

      let history = case model.detail_history {
        [] -> []
        revisions -> [
          ui.br(),
          ui.text_styled(
            "History ("
              <> int.to_string(list.length(revisions))
              <> " revisions):",
            Some(style.Yellow),
            None,
          ),
          ..list.map(revisions, fn(revision: Revision) {
            ui.text(
              "  ["
              <> store.unix_seconds_to_rfc3339(revision.edited_at)
              <> "] "
              <> revision.body,
            )
          })
        ]
      }

      let tag_row = [
        ui.hr(),
        ui.row([
          ui.input("Tag", model.tag_input, style.Px(20), TagChanged),
          ui.button("t toggle", key.Char("t"), SubmitToggleTag(id)),
        ]),
      ]

      let actions = [
        ui.hr(),
        ui.row([
          ui.button("e edit", key.Char("e"), GoToEdit(id)),
          ui.button("d delete", key.Char("d"), AskDelete(id)),
          ui.button("esc back", key.Esc, GoToList),
        ]),
        view_exit_hint(),
        view_status(model),
      ]

      let children = list.flatten([info, history, tag_row, actions])

      ui.box(children, Some(title))
      |> layout.center(style.Px(60), style.Fill)
    }
  }
}

fn view_create(model: Model) -> shore.Node(Message) {
  ui.box(
    [
      ui.input("Title", model.title_input, style.Px(50), TitleChanged),
      ui.input_submit(
        "Body",
        model.body_input,
        style.Px(50),
        BodyChanged,
        SubmitCreate,
        False,
      ),
      ui.hr(),
      ui.row([
        ui.button("enter save", key.Enter, SubmitCreate),
        ui.button("esc cancel", key.Esc, GoToList),
      ]),
      view_exit_hint(),
      view_status(model),
    ],
    Some("new note"),
  )
  |> layout.center(style.Px(60), style.Fill)
}

fn view_edit(model: Model, id: Int) -> shore.Node(Message) {
  let title_text = case model.detail_note {
    Ok(note) -> note.title
    Error(_) -> ""
  }

  ui.box(
    [
      ui.text("Title: " <> title_text),
      ui.input_submit(
        "Body",
        model.body_input,
        style.Px(50),
        BodyChanged,
        SubmitEdit(id),
        False,
      ),
      ui.hr(),
      ui.row([
        ui.button("enter save", key.Enter, SubmitEdit(id)),
        ui.button("esc cancel", key.Esc, GoToDetail(id)),
      ]),
      view_exit_hint(),
      view_status(model),
    ],
    Some("edit note #" <> int.to_string(id)),
  )
  |> layout.center(style.Px(60), style.Fill)
}

fn view_confirm_delete(model: Model, id: Int) -> shore.Node(Message) {
  let note_title = case
    list.find(model.notes, fn(pair) {
      let #(note_id, _) = pair
      note_id == id
    })
  {
    Ok(#(_, note)) -> note.title
    Error(_) ->
      case model.detail_note {
        Ok(note) -> note.title
        Error(_) -> "?"
      }
  }

  ui.box(
    [
      ui.text("Delete \"" <> note_title <> "\"?"),
      ui.br(),
      ui.text("This will remove the note, its tags,"),
      ui.text("and all edit history."),
      ui.hr(),
      ui.row([
        ui.button("y delete", key.Char("y"), ConfirmDeleteNote(id)),
        ui.button("n cancel", key.Char("n"), CancelDelete),
      ]),
      view_exit_hint(),
      ui.keybind(key.Esc, CancelDelete),
    ],
    Some("delete note #" <> int.to_string(id)),
  )
  |> layout.center(style.Px(50), style.Px(10))
}

// --- Helpers ---

fn get_selected_id(model: Model) -> Result(Int, Nil) {
  model.notes
  |> list.drop(model.selected_index)
  |> list.first
  |> result.map(fn(pair) {
    let #(id, _) = pair
    id
  })
}

fn view_exit_hint() -> shore.Node(Message) {
  ui.text_styled("ctrl-x exit", Some(style.White), None)
}

fn view_status(model: Model) -> shore.Node(Message) {
  case model.status_message {
    "" -> ui.text("")
    message -> {
      let color = case model.status_is_error {
        True -> Some(style.Red)
        False -> Some(style.Green)
      }
      ui.text_styled(message, color, None)
    }
  }
}
