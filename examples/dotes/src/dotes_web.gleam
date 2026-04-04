import dotes/store.{type Store}
import dotes/types.{type Note, type Revision}
import gleam/bytes_tree
import gleam/erlang/application
import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component
import mist.{type Connection, type ResponseData}
import slate

// --- Types ---

type Screen {
  NoteList
  NoteDetail(id: Int)
  NoteCreate
  NoteEdit(id: Int)
  ConfirmDelete(id: Int)
}

type Model {
  Model(
    store: Store,
    screen: Screen,
    notes: List(#(Int, Note)),
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

type Msg {
  // Async results
  NotesLoaded(Result(List(#(Int, Note)), String))
  NoteDetailLoaded(Result(#(Note, List(String), List(Revision)), String))
  NoteCreated(Result(Int, String))
  NoteUpdated(Result(Nil, String))
  NoteDeleted(Result(Nil, String))
  TagToggled(Result(Bool, String))
  // Navigation
  GoToList
  GoToCreate
  GoToDetail(Int)
  GoToEdit(Int)
  AskDelete(Int)
  CancelDelete
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

pub fn main() {
  let assert Ok(s) = store.open()

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> serve_html()
        ["lustre", "runtime.mjs"] -> serve_runtime()
        ["ws"] -> serve_ws(req, s)
        _ ->
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_tree.new()))
      }
    }
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(3000)
    |> mist.start

  io.println("dotes web running at http://localhost:3000")
  process.sleep_forever()
}

// --- HTTP Handlers ---

fn serve_html() -> Response(ResponseData) {
  let page =
    html.html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "dotes"),
        html.script(
          [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
          "",
        ),
        html.style([], css()),
      ]),
      html.body([], [
        server_component.element(
          [
            server_component.route("/ws"),
            server_component.method(server_component.WebSocket),
          ],
          [],
        ),
      ]),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(page))
  |> response.set_header("content-type", "text/html")
}

fn serve_runtime() -> Response(ResponseData) {
  let assert Ok(lustre_priv) = application.priv_directory("lustre")
  let path = lustre_priv <> "/static/lustre-server-component.mjs"

  case mist.send_file(path, offset: 0, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.set_header("content-type", "application/javascript")
      |> response.set_body(file)
    Error(_) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}

// --- WebSocket Handler ---

type Socket {
  Socket(
    component: lustre.Runtime(Msg),
    self: Subject(server_component.ClientMessage(Msg)),
  )
}

type SocketMessage =
  server_component.ClientMessage(Msg)

type SocketInit =
  #(Socket, Option(Selector(SocketMessage)))

fn serve_ws(
  req: Request(Connection),
  s: Store,
) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_conn) -> SocketInit { init_socket(s) },
    handler: loop_socket,
    on_close: close_socket,
  )
}

fn init_socket(s: Store) -> SocketInit {
  let app = lustre.application(fn(_) { init(s) }, update, view)
  let assert Ok(component) = lustre.start_server_component(app, Nil)

  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  server_component.register_subject(self)
  |> lustre.send(to: component)

  #(Socket(component:, self:), Some(selector))
}

fn loop_socket(
  state: Socket,
  message: mist.WebsocketMessage(SocketMessage),
  connection: mist.WebsocketConnection,
) -> mist.Next(Socket, SocketMessage) {
  case message {
    mist.Text(text) -> {
      case json.parse(text, server_component.runtime_message_decoder()) {
        Ok(runtime_message) -> lustre.send(state.component, runtime_message)
        Error(_) -> Nil
      }
      mist.continue(state)
    }

    mist.Binary(_) -> mist.continue(state)

    mist.Custom(client_message) -> {
      let msg = server_component.client_message_to_json(client_message)
      let assert Ok(_) =
        mist.send_text_frame(connection, json.to_string(msg))
      mist.continue(state)
    }

    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn close_socket(state: Socket) -> Nil {
  lustre.shutdown()
  |> lustre.send(to: state.component)
}

// --- Init ---

fn init(s: Store) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      store: s,
      screen: NoteList,
      notes: [],
      detail_note: Error(Nil),
      detail_tags: [],
      detail_history: [],
      title_input: "",
      body_input: "",
      tag_input: "",
      status_message: "",
      status_is_error: False,
    )
  #(model, load_notes_effect(s))
}

// --- Effects ---

fn load_notes_effect(s: Store) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    case store.list_notes(s) {
      Ok(notes) -> dispatch(NotesLoaded(Ok(notes)))
      Error(e) -> dispatch(NotesLoaded(Error(slate.error_message(e))))
    }
  })
}

fn load_detail_effect(s: Store, id: Int) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    case store.get_note(s, id) {
      Error(e) -> dispatch(NoteDetailLoaded(Error(slate.error_message(e))))
      Ok(note) -> {
        let tags = store.get_tags(s, id) |> result.unwrap([])
        let history = store.get_history(s, id) |> result.unwrap([])
        dispatch(NoteDetailLoaded(Ok(#(note, tags, history))))
      }
    }
  })
}

fn create_note_effect(s: Store, title: String, body: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    case store.create_note(s, title: title, body: body) {
      Ok(id) -> dispatch(NoteCreated(Ok(id)))
      Error(e) -> dispatch(NoteCreated(Error(slate.error_message(e))))
    }
  })
}

fn update_note_effect(s: Store, id: Int, body: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    case store.update_note(s, id: id, body: body) {
      Ok(Nil) -> dispatch(NoteUpdated(Ok(Nil)))
      Error(e) -> dispatch(NoteUpdated(Error(slate.error_message(e))))
    }
  })
}

fn toggle_tag_effect(s: Store, id: Int, tag: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    case store.toggle_tag(s, id: id, tag: tag) {
      Ok(added) -> dispatch(TagToggled(Ok(added)))
      Error(e) -> dispatch(TagToggled(Error(slate.error_message(e))))
    }
  })
}

fn delete_note_effect(s: Store, id: Int) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    case store.delete_note(s, id) {
      Ok(Nil) -> dispatch(NoteDeleted(Ok(Nil)))
      Error(e) -> dispatch(NoteDeleted(Error(slate.error_message(e))))
    }
  })
}

// --- Update ---

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // Data loaded
    NotesLoaded(Ok(notes)) -> #(Model(..model, notes: notes), effect.none())
    NotesLoaded(Error(e)) -> #(
      Model(..model, status_message: e, status_is_error: True),
      effect.none(),
    )

    NoteDetailLoaded(Ok(#(note, tags, history))) -> #(
      Model(
        ..model,
        detail_note: Ok(note),
        detail_tags: tags,
        detail_history: history,
      ),
      effect.none(),
    )
    NoteDetailLoaded(Error(e)) -> #(
      Model(..model, status_message: e, status_is_error: True, screen: NoteList),
      load_notes_effect(model.store),
    )

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
      load_notes_effect(model.store),
    )
    GoToCreate -> #(
      Model(
        ..model,
        screen: NoteCreate,
        title_input: "",
        body_input: "",
        status_message: "",
      ),
      effect.none(),
    )
    GoToDetail(id) -> #(
      Model(..model, screen: NoteDetail(id), tag_input: "", status_message: ""),
      load_detail_effect(model.store, id),
    )
    GoToEdit(id) -> {
      let body = case model.detail_note {
        Ok(note) -> note.body
        Error(_) -> ""
      }
      #(
        Model(..model, screen: NoteEdit(id), body_input: body, status_message: ""),
        effect.none(),
      )
    }
    AskDelete(id) -> #(Model(..model, screen: ConfirmDelete(id)), effect.none())
    CancelDelete -> #(Model(..model, screen: NoteList), effect.none())

    // Form input
    TitleChanged(val) -> #(Model(..model, title_input: val), effect.none())
    BodyChanged(val) -> #(Model(..model, body_input: val), effect.none())
    TagChanged(val) -> #(Model(..model, tag_input: val), effect.none())

    // Actions
    SubmitCreate -> #(
      model,
      create_note_effect(model.store, model.title_input, model.body_input),
    )
    SubmitEdit(id) -> #(
      model,
      update_note_effect(model.store, id, model.body_input),
    )
    SubmitToggleTag(id) -> {
      case model.tag_input {
        "" -> #(model, effect.none())
        tag -> #(model, toggle_tag_effect(model.store, id, tag))
      }
    }
    ConfirmDeleteNote(id) -> #(model, delete_note_effect(model.store, id))

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
      load_notes_effect(model.store),
    )
    NoteCreated(Error(e)) -> #(
      Model(..model, status_message: e, status_is_error: True),
      effect.none(),
    )

    NoteUpdated(Ok(Nil)) -> {
      let id = case model.screen {
        NoteEdit(id) -> id
        _ -> 0
      }
      #(
        Model(
          ..model,
          screen: NoteDetail(id),
          status_message: "Note updated",
          status_is_error: False,
        ),
        load_detail_effect(model.store, id),
      )
    }
    NoteUpdated(Error(e)) -> #(
      Model(..model, status_message: e, status_is_error: True),
      effect.none(),
    )

    NoteDeleted(Ok(Nil)) -> #(
      Model(
        ..model,
        screen: NoteList,
        status_message: "Note deleted",
        status_is_error: False,
      ),
      load_notes_effect(model.store),
    )
    NoteDeleted(Error(e)) -> #(
      Model(..model, status_message: e, status_is_error: True),
      effect.none(),
    )

    TagToggled(Ok(added)) -> {
      let id = case model.screen {
        NoteDetail(id) -> id
        _ -> 0
      }
      let msg = case added {
        True -> "Tag added"
        False -> "Tag removed"
      }
      #(
        Model(
          ..model,
          tag_input: "",
          status_message: msg,
          status_is_error: False,
        ),
        load_detail_effect(model.store, id),
      )
    }
    TagToggled(Error(e)) -> #(
      Model(..model, status_message: e, status_is_error: True),
      effect.none(),
    )
  }
}

// --- View ---

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("container")], [
    case model.screen {
      NoteList -> view_list(model)
      NoteDetail(id) -> view_detail(model, id)
      NoteCreate -> view_create(model)
      NoteEdit(id) -> view_edit(model, id)
      ConfirmDelete(id) -> view_confirm_delete(model, id)
    },
    view_status(model),
  ])
}

fn view_list(model: Model) -> Element(Msg) {
  html.section([attribute.class("box")], [
    html.h2([], [html.text("dotes")]),
    case model.notes {
      [] ->
        html.p([attribute.class("empty")], [
          html.text("No notes yet. Click \"New Note\" to create one."),
        ])
      notes ->
        html.ul(
          [attribute.class("note-list")],
          list.map(notes, fn(pair) {
            let #(id, note) = pair
            html.li([], [
              html.a(
                [
                  attribute.href("#"),
                  event.on_click(GoToDetail(id)),
                ],
                [
                  html.span([attribute.class("note-id")], [
                    html.text("#" <> int.to_string(id)),
                  ]),
                  html.span([attribute.class("note-title")], [
                    html.text(note.title),
                  ]),
                  html.span([attribute.class("note-date")], [
                    html.text(types.format_timestamp(note.created_at)),
                  ]),
                ],
              ),
            ])
          }),
        )
    },
    html.div([attribute.class("actions")], [
      html.button([event.on_click(GoToCreate)], [html.text("New Note")]),
    ]),
  ])
}

fn view_detail(model: Model, id: Int) -> Element(Msg) {
  html.section([attribute.class("box")], [
    html.h2([], [html.text("Note #" <> int.to_string(id))]),
    case model.detail_note {
      Error(_) -> html.p([], [html.text("Loading...")])
      Ok(note) ->
        element.fragment([
          html.table([attribute.class("kv-table")], [
            kv_row("Title", note.title),
            kv_row("Body", note.body),
            kv_row("Created", types.format_timestamp(note.created_at)),
            kv_row("Tags", case model.detail_tags {
              [] -> "(none)"
              tags -> string.join(tags, ", ")
            }),
          ]),
          view_history(model.detail_history),
          html.hr([]),
          html.div([attribute.class("tag-form")], [
            html.input([
              attribute.placeholder("Tag name"),
              attribute.value(model.tag_input),
              event.on_input(TagChanged),
            ]),
            html.button([event.on_click(SubmitToggleTag(id))], [
              html.text("Toggle Tag"),
            ]),
          ]),
          html.hr([]),
          html.div([attribute.class("actions")], [
            html.button([event.on_click(GoToEdit(id))], [html.text("Edit")]),
            html.button(
              [
                attribute.class("danger"),
                event.on_click(AskDelete(id)),
              ],
              [html.text("Delete")],
            ),
            html.button([event.on_click(GoToList)], [html.text("Back")]),
          ]),
        ])
    },
  ])
}

fn view_history(revisions: List(Revision)) -> Element(Msg) {
  case revisions {
    [] -> element.none()
    _ ->
      html.div([attribute.class("history")], [
        html.h3([], [
          html.text(
            "History ("
            <> int.to_string(list.length(revisions))
            <> " revisions)",
          ),
        ]),
        html.ul(
          [],
          list.map(revisions, fn(rev) {
            html.li([], [
              html.span([attribute.class("note-date")], [
                html.text(types.format_timestamp(rev.edited_at)),
              ]),
              html.text(" " <> rev.body),
            ])
          }),
        ),
      ])
  }
}

fn view_create(model: Model) -> Element(Msg) {
  html.section([attribute.class("box")], [
    html.h2([], [html.text("New Note")]),
    html.div([attribute.class("form")], [
      html.label([], [
        html.text("Title"),
        html.input([
          attribute.value(model.title_input),
          attribute.placeholder("Note title"),
          event.on_input(TitleChanged),
        ]),
      ]),
      html.label([], [
        html.text("Body"),
        html.input([
          attribute.value(model.body_input),
          attribute.placeholder("Note body"),
          event.on_input(BodyChanged),
        ]),
      ]),
    ]),
    html.div([attribute.class("actions")], [
      html.button([event.on_click(SubmitCreate)], [html.text("Save")]),
      html.button([event.on_click(GoToList)], [html.text("Cancel")]),
    ]),
  ])
}

fn view_edit(model: Model, id: Int) -> Element(Msg) {
  let title_text = case model.detail_note {
    Ok(note) -> note.title
    Error(_) -> ""
  }

  html.section([attribute.class("box")], [
    html.h2([], [html.text("Edit Note #" <> int.to_string(id))]),
    html.div([attribute.class("form")], [
      html.label([], [
        html.text("Title"),
        html.input([
          attribute.value(title_text),
          attribute.disabled(True),
        ]),
      ]),
      html.label([], [
        html.text("Body"),
        html.input([
          attribute.value(model.body_input),
          attribute.placeholder("Note body"),
          event.on_input(BodyChanged),
        ]),
      ]),
    ]),
    html.div([attribute.class("actions")], [
      html.button([event.on_click(SubmitEdit(id))], [html.text("Save")]),
      html.button([event.on_click(GoToDetail(id))], [html.text("Cancel")]),
    ]),
  ])
}

fn view_confirm_delete(model: Model, id: Int) -> Element(Msg) {
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

  html.section([attribute.class("box confirm")], [
    html.h2([], [html.text("Delete Note #" <> int.to_string(id))]),
    html.p([], [
      html.text("Delete \"" <> note_title <> "\"?"),
    ]),
    html.p([attribute.class("subtle")], [
      html.text("This will remove the note, its tags, and all edit history."),
    ]),
    html.div([attribute.class("actions")], [
      html.button(
        [attribute.class("danger"), event.on_click(ConfirmDeleteNote(id))],
        [html.text("Yes, Delete")],
      ),
      html.button([event.on_click(CancelDelete)], [html.text("Cancel")]),
    ]),
  ])
}

// --- Helpers ---

fn kv_row(key: String, value: String) -> Element(Msg) {
  html.tr([], [
    html.th([], [html.text(key)]),
    html.td([], [html.text(value)]),
  ])
}

fn view_status(model: Model) -> Element(Msg) {
  case model.status_message {
    "" -> element.none()
    msg -> {
      let class = case model.status_is_error {
        True -> "status error"
        False -> "status success"
      }
      html.div([attribute.class(class)], [html.text(msg)])
    }
  }
}

// --- CSS ---

fn css() -> String {
  "
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
    background: #1a1a2e; color: #e0e0e0;
    display: flex; justify-content: center;
    padding: 2rem;
  }
  .container { max-width: 40rem; width: 100%; }
  .box {
    border: 1px solid #333; border-radius: 8px;
    padding: 1.5rem; background: #16213e;
  }
  .box h2 { margin-bottom: 1rem; color: #64ffda; }
  .box h3 { margin: 0.5rem 0; color: #ffd54f; font-size: 0.95rem; }
  .confirm p { margin-bottom: 0.5rem; }
  .subtle { color: #888; font-size: 0.9rem; }

  .note-list { list-style: none; }
  .note-list li { border-bottom: 1px solid #222; }
  .note-list li:last-child { border-bottom: none; }
  .note-list a {
    display: flex; gap: 1rem; padding: 0.6rem 0.4rem;
    color: #e0e0e0; text-decoration: none; border-radius: 4px;
  }
  .note-list a:hover { background: #1a1a3e; }
  .note-id { color: #64ffda; font-weight: 600; min-width: 2.5rem; }
  .note-title { flex: 1; }
  .note-date { color: #888; font-size: 0.85rem; }
  .empty { color: #888; padding: 1rem 0; }

  .kv-table { width: 100%; border-collapse: collapse; }
  .kv-table th {
    text-align: left; padding: 0.3rem 1rem 0.3rem 0;
    color: #888; font-weight: 500; width: 5rem; vertical-align: top;
  }
  .kv-table td { padding: 0.3rem 0; }

  .history ul { list-style: none; padding-left: 0.5rem; }
  .history li { padding: 0.2rem 0; font-size: 0.9rem; }

  hr { border: none; border-top: 1px solid #333; margin: 1rem 0; }

  .form { display: flex; flex-direction: column; gap: 0.75rem; margin-bottom: 1rem; }
  .form label { display: flex; flex-direction: column; gap: 0.25rem; color: #888; font-size: 0.85rem; }
  .tag-form { display: flex; gap: 0.5rem; align-items: center; }

  input {
    background: #0f3460; border: 1px solid #444; border-radius: 4px;
    padding: 0.5rem; color: #e0e0e0; font-size: 1rem; width: 100%;
  }
  input:focus { outline: none; border-color: #64ffda; }
  input:disabled { opacity: 0.5; }
  .tag-form input { width: auto; flex: 1; }

  .actions { display: flex; gap: 0.5rem; margin-top: 1rem; }
  button {
    background: #0f3460; border: 1px solid #444; border-radius: 4px;
    padding: 0.5rem 1rem; color: #e0e0e0; cursor: pointer; font-size: 0.9rem;
  }
  button:hover { background: #1a4a80; border-color: #64ffda; }
  button.danger { border-color: #ff5252; color: #ff5252; }
  button.danger:hover { background: #3e1111; }

  .status {
    margin-top: 1rem; padding: 0.5rem 1rem;
    border-radius: 4px; font-size: 0.9rem;
  }
  .status.success { background: #1b3a2a; color: #64ffda; border: 1px solid #2e7d5a; }
  .status.error { background: #3e1111; color: #ff5252; border: 1px solid #ff5252; }
  "
}
