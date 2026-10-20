import dotes/lifecycle
import dotes/request
import dotes/store.{type Note, type Revision, type Store}
import gleam/bytes_tree
import gleam/erlang/application
import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request as http_request
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import glisten/transport
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component
import mist.{type Connection, type ResponseData}

// --- Types ---

/// The screen currently shown in the browser.
pub type Screen {
  NoteList
  NoteDetail(id: Int)
  NoteCreate
  NoteEdit(id: Int)
  ConfirmDelete(id: Int)
}

/// A status message and its meaning.
pub type Status {
  NoStatus
  Success(String)
  Failure(String)
}

/// Browser state, separate from effects so updates can be tested directly.
pub type Model {
  Model(
    store: Store,
    request: request.Id,
    screen: Screen,
    notes: List(#(Int, Note)),
    detail_note: Result(Note, Nil),
    detail_tags: Result(List(String), store.Error),
    detail_history: Result(List(Revision), store.Error),
    detail_loading: Bool,
    title_input: String,
    body_input: String,
    tag_input: String,
    status: Status,
  )
}

/// Input events and note-specific effect results.
pub type Message {
  // Async results
  NotesLoaded(request.Id, Result(List(#(Int, Note)), String))
  NoteDetailLoaded(request.Id, Int, Result(store.Detail, String))
  NoteCreated(request.Id, Result(Int, String))
  NoteUpdated(request.Id, Int, Result(Nil, String))
  NoteDeleted(request.Id, Result(Nil, String))
  TagToggled(request.Id, Int, Result(Bool, String))
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

pub fn main() -> Nil {
  lifecycle.run(".dotes", start_server)
}

fn start_server(store: Store) -> Result(process.Pid, String) {
  let started =
    fn(request: http_request.Request(Connection)) -> Response(ResponseData) {
      case http_request.path_segments(request) {
        [] -> serve_html()
        ["lustre", "runtime.mjs"] -> serve_runtime()
        ["ws"] -> serve_websocket(request, store)
        _ ->
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_tree.new()))
      }
    }
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(3000)
    |> mist.start

  case started {
    Error(_) -> Error("Cannot start the dotes web server")
    Ok(server) -> {
      io.println("dotes web running at http://localhost:3000")
      Ok(server.pid)
    }
  }
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

/// Serve the installed Lustre browser runtime.
pub fn serve_runtime() -> Response(ResponseData) {
  let file = {
    use lustre_private_directory <- result.try(
      application.priv_directory("lustre")
      |> result.map_error(fn(_) { "Cannot locate the Lustre runtime directory" }),
    )
    mist.send_file(
      lustre_private_directory <> "/static/lustre-server-component.mjs",
      offset: 0,
      limit: None,
    )
    |> result.map_error(fn(_) { "Cannot read the Lustre browser runtime" })
  }
  case file {
    Ok(file) ->
      response.new(200)
      |> response.set_header("content-type", "application/javascript")
      |> response.set_body(file)
    Error(message) -> {
      io.println(message)
      response.new(500)
      |> response.set_body(mist.Bytes(bytes_tree.from_string(message)))
    }
  }
}

// --- WebSocket Handler ---

/// The component owned by one WebSocket process and its client subject.
pub type Socket {
  Socket(
    component: lustre.Runtime(Message),
    self: Subject(server_component.ClientMessage(Message)),
  )
}

/// Messages sent from the component to its browser client.
pub type SocketMessage =
  server_component.ClientMessage(Message)

/// Initial state and message selector required by Mist.
pub type SocketInit =
  #(Socket, Option(Selector(SocketMessage)))

fn serve_websocket(
  request: http_request.Request(Connection),
  store: Store,
) -> Response(ResponseData) {
  mist.websocket(
    request: request,
    on_init: fn(connection) -> SocketInit {
      init_socket(store)
      |> finish_socket_init(connection, _)
    },
    handler: loop_socket,
    on_close: close_socket,
  )
}

/// Start a component in its owning WebSocket process.
pub fn init_socket(store: Store) -> Result(SocketInit, lustre.Error) {
  let application = lustre.application(fn(_) { init(store) }, update, view)
  use component <- result.try(lustre.start_server_component(application, Nil))

  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  server_component.register_subject(self)
  |> lustre.send(to: component)

  Ok(#(Socket(component:, self:), Some(selector)))
}

/// Adapt a fallible component start to Mist's infallible init callback.
pub fn finish_socket_init(
  connection: mist.WebsocketConnection,
  started: Result(SocketInit, lustre.Error),
) -> SocketInit {
  case started {
    Ok(initialised) -> initialised
    Error(_) -> {
      io.println("Cannot start the dotes WebSocket component")
      // Mist cannot return an init error. Close the upgraded connection before
      // exiting so its factory supervisor observes a failed child start.
      case transport.close(connection.transport, connection.socket) {
        Ok(Nil) -> Nil
        Error(_) -> io.println("Cannot close the failed dotes WebSocket")
      }
      exit_socket_init("Cannot start the dotes WebSocket component")
    }
  }
}

@external(erlang, "erlang", "exit")
fn exit_socket_init(reason: String) -> SocketInit

/// Handle frames, stopping on send failure so Mist invokes close_socket.
pub fn loop_socket(
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
      let message = server_component.client_message_to_json(client_message)
      case mist.send_text_frame(connection, json.to_string(message)) {
        Ok(Nil) -> mist.continue(state)
        Error(_) -> {
          io.println("Cannot send a dotes WebSocket frame")
          mist.stop()
        }
      }
    }

    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

/// Shut down the component when Mist closes its connection.
pub fn close_socket(state: Socket) -> Nil {
  lustre.shutdown()
  |> lustre.send(to: state.component)
}

// --- Init ---

/// Create the browser state and its initial load effect.
pub fn init(store: Store) -> #(Model, Effect(Message)) {
  let model =
    Model(
      store: store,
      request: request.new(),
      screen: NoteList,
      notes: [],
      detail_note: Error(Nil),
      detail_tags: Ok([]),
      detail_history: Ok([]),
      detail_loading: False,
      title_input: "",
      body_input: "",
      tag_input: "",
      status: NoStatus,
    )
  #(model, load_notes_effect(store, model.request))
}

// --- Effects ---

fn load_notes_effect(store: Store, context: request.Id) -> Effect(Message) {
  effect.from(fn(dispatch) {
    case store.list_notes(store) {
      Ok(notes) -> dispatch(NotesLoaded(context, Ok(notes)))
      Error(error) ->
        dispatch(NotesLoaded(context, Error(store.error_message(error))))
    }
  })
}

fn load_detail_effect(
  store: Store,
  id: Int,
  context: request.Id,
) -> Effect(Message) {
  effect.from(fn(dispatch) {
    case store.get_detail(store, id) {
      Error(error) ->
        dispatch(NoteDetailLoaded(
          context,
          id,
          Error(store.error_message(error)),
        ))
      Ok(detail) -> dispatch(NoteDetailLoaded(context, id, Ok(detail)))
    }
  })
}

fn create_note_effect(
  store: Store,
  title: String,
  body: String,
  context: request.Id,
) -> Effect(Message) {
  effect.from(fn(dispatch) {
    case store.create_note(store, title: title, body: body) {
      Ok(id) -> dispatch(NoteCreated(context, Ok(id)))
      Error(error) ->
        dispatch(NoteCreated(context, Error(store.error_message(error))))
    }
  })
}

fn update_note_effect(
  store: Store,
  id: Int,
  body: String,
  context: request.Id,
) -> Effect(Message) {
  effect.from(fn(dispatch) {
    case store.update_note(store, id: id, body: body) {
      Ok(Nil) -> dispatch(NoteUpdated(context, id, Ok(Nil)))
      Error(error) ->
        dispatch(NoteUpdated(context, id, Error(store.error_message(error))))
    }
  })
}

fn toggle_tag_effect(
  store: Store,
  id: Int,
  tag: String,
  context: request.Id,
) -> Effect(Message) {
  effect.from(fn(dispatch) {
    case store.toggle_tag(store, id: id, tag: tag) {
      Ok(added) -> dispatch(TagToggled(context, id, Ok(added)))
      Error(error) ->
        dispatch(TagToggled(context, id, Error(store.error_message(error))))
    }
  })
}

fn delete_note_effect(
  store: Store,
  id: Int,
  context: request.Id,
) -> Effect(Message) {
  effect.from(fn(dispatch) {
    case store.delete_note(store, id) {
      Ok(Nil) -> dispatch(NoteDeleted(context, Ok(Nil)))
      Error(error) ->
        dispatch(NoteDeleted(context, Error(store.error_message(error))))
    }
  })
}

// --- Update ---

/// Apply an event without running its returned effect.
pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    NotesLoaded(context, _)
    | NoteDetailLoaded(context, _, _)
    | NoteCreated(context, _)
    | NoteUpdated(context, _, _)
    | NoteDeleted(context, _)
    | TagToggled(context, _, _) ->
      case context == model.request {
        False -> #(model, effect.none())
        True ->
          update_current(
            Model(..model, request: request.next(context)),
            message,
          )
      }
    GoToList
    | GoToCreate
    | GoToDetail(_)
    | GoToEdit(_)
    | AskDelete(_)
    | CancelDelete ->
      update_current(
        Model(
          ..model,
          request: request.navigate(model.request),
          detail_loading: False,
        ),
        message,
      )
    TitleChanged(value) ->
      update_input(model, message, value != model.title_input)
    BodyChanged(value) ->
      update_input(model, message, value != model.body_input)
    TagChanged(value) -> update_input(model, message, value != model.tag_input)
    SubmitToggleTag(_) if model.tag_input == "" -> #(model, effect.none())
    SubmitCreate | SubmitEdit(_) | SubmitToggleTag(_) | ConfirmDeleteNote(_) ->
      update_current(
        Model(..model, request: request.next(model.request)),
        message,
      )
  }
}

fn update_input(
  model: Model,
  message: Message,
  changed: Bool,
) -> #(Model, Effect(Message)) {
  case changed {
    False -> #(model, effect.none())
    True -> {
      let #(model, _) =
        update_current(
          Model(..model, request: request.revise(model.request)),
          message,
        )
      #(model, refresh_detail(model))
    }
  }
}

fn refresh_detail(model: Model) -> Effect(Message) {
  case model.screen {
    NoteDetail(id) if model.detail_loading ->
      load_detail_effect(model.store, id, model.request)
    NoteList | NoteCreate | NoteEdit(_) | ConfirmDelete(_) | NoteDetail(_) ->
      effect.none()
  }
}

fn update_current(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    // Data loaded
    NotesLoaded(_, Ok(notes)) -> #(Model(..model, notes: notes), effect.none())
    NotesLoaded(_, Error(error_message)) -> #(
      Model(..model, status: Failure(error_message)),
      effect.none(),
    )

    NoteDetailLoaded(_, id, result) ->
      case model.screen {
        NoteDetail(current_id) if current_id == id ->
          case result {
            Ok(store.Detail(note, tags, history)) -> #(
              Model(
                ..model,
                detail_note: Ok(note),
                detail_tags: tags,
                detail_history: history,
                detail_loading: False,
              ),
              effect.none(),
            )
            Error(error_message) -> #(
              Model(
                ..model,
                status: Failure(error_message),
                screen: NoteList,
                detail_loading: False,
              ),
              load_notes_effect(model.store, model.request),
            )
          }
        NoteList
        | NoteCreate
        | NoteEdit(_)
        | ConfirmDelete(_)
        | NoteDetail(_) -> #(model, effect.none())
      }

    // Navigation
    GoToList -> #(
      Model(
        ..model,
        screen: NoteList,
        title_input: "",
        body_input: "",
        tag_input: "",
        status: NoStatus,
      ),
      load_notes_effect(model.store, model.request),
    )
    GoToCreate -> #(
      Model(
        ..model,
        screen: NoteCreate,
        title_input: "",
        body_input: "",
        status: NoStatus,
      ),
      effect.none(),
    )
    GoToDetail(id) -> #(
      Model(
        ..model,
        screen: NoteDetail(id),
        detail_note: Error(Nil),
        detail_tags: Ok([]),
        detail_history: Ok([]),
        detail_loading: True,
        tag_input: "",
        status: NoStatus,
      ),
      load_detail_effect(model.store, id, model.request),
    )
    GoToEdit(id) -> {
      let body = case model.detail_note {
        Ok(note) -> note.body
        Error(_) -> ""
      }
      #(
        Model(..model, screen: NoteEdit(id), body_input: body, status: NoStatus),
        effect.none(),
      )
    }
    AskDelete(id) -> #(Model(..model, screen: ConfirmDelete(id)), effect.none())
    CancelDelete -> #(
      Model(..model, screen: NoteList),
      load_notes_effect(model.store, model.request),
    )

    // Form input
    TitleChanged(value) -> #(Model(..model, title_input: value), effect.none())
    BodyChanged(value) -> #(Model(..model, body_input: value), effect.none())
    TagChanged(value) -> #(Model(..model, tag_input: value), effect.none())

    // Actions
    SubmitCreate -> #(
      model,
      create_note_effect(
        model.store,
        model.title_input,
        model.body_input,
        model.request,
      ),
    )
    SubmitEdit(id) -> #(
      model,
      update_note_effect(model.store, id, model.body_input, model.request),
    )
    SubmitToggleTag(id) -> {
      case model.tag_input {
        "" -> #(model, effect.none())
        tag -> #(model, toggle_tag_effect(model.store, id, tag, model.request))
      }
    }
    ConfirmDeleteNote(id) -> #(
      model,
      delete_note_effect(model.store, id, model.request),
    )

    // Action results
    NoteCreated(_, Ok(id)) -> #(
      Model(
        ..model,
        screen: NoteList,
        title_input: "",
        body_input: "",
        status: Success("Created note #" <> int.to_string(id)),
      ),
      load_notes_effect(model.store, model.request),
    )
    NoteCreated(_, Error(error_message)) -> #(
      Model(..model, status: Failure(error_message)),
      effect.none(),
    )

    NoteUpdated(_, id, result) ->
      case model.screen {
        NoteEdit(current_id) if current_id == id ->
          case result {
            Ok(Nil) -> #(
              Model(
                ..model,
                screen: NoteDetail(id),
                detail_note: Error(Nil),
                detail_loading: True,
                status: Success("Note updated"),
              ),
              load_detail_effect(model.store, id, model.request),
            )
            Error(error_message) -> #(
              Model(..model, status: Failure(error_message)),
              effect.none(),
            )
          }
        NoteList
        | NoteCreate
        | NoteDetail(_)
        | ConfirmDelete(_)
        | NoteEdit(_) -> #(model, effect.none())
      }

    NoteDeleted(_, Ok(Nil)) -> #(
      Model(..model, screen: NoteList, status: Success("Note deleted")),
      load_notes_effect(model.store, model.request),
    )
    NoteDeleted(_, Error(error_message)) -> #(
      Model(..model, status: Failure(error_message)),
      effect.none(),
    )

    TagToggled(_, id, result) ->
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
                  status: Success(message),
                  detail_loading: True,
                ),
                load_detail_effect(model.store, id, model.request),
              )
            }
            Error(error_message) -> #(
              Model(..model, status: Failure(error_message)),
              refresh_detail(model),
            )
          }
        NoteList
        | NoteCreate
        | NoteEdit(_)
        | ConfirmDelete(_)
        | NoteDetail(_) -> #(model, effect.none())
      }
  }
}

// --- View ---

/// Render the current browser screen.
pub fn view(model: Model) -> Element(Message) {
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

fn view_list(model: Model) -> Element(Message) {
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
                    html.text(store.unix_seconds_to_rfc3339(note.created_at)),
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

fn view_detail(model: Model, id: Int) -> Element(Message) {
  html.section([attribute.class("box")], [
    html.h2([], [html.text("Note #" <> int.to_string(id))]),
    case model.detail_note {
      Error(_) -> html.p([], [html.text("Loading...")])
      Ok(note) ->
        element.fragment([
          html.table([attribute.class("kv-table")], [
            key_value_row("Title", note.title),
            key_value_row("Body", note.body),
            key_value_row(
              "Created",
              store.unix_seconds_to_rfc3339(note.created_at),
            ),
            key_value_row("Tags", case model.detail_tags {
              Ok([]) -> "(none)"
              Ok(tags) -> string.join(tags, ", ")
              Error(error) -> "Tags unavailable: " <> store.error_message(error)
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

fn view_history(
  revisions: Result(List(Revision), store.Error),
) -> Element(Message) {
  case revisions {
    Error(error) ->
      html.p([], [
        html.text("History unavailable: " <> store.error_message(error)),
      ])
    Ok([]) -> element.none()
    Ok(revisions) ->
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
          list.map(revisions, fn(revision) {
            html.li([], [
              html.span([attribute.class("note-date")], [
                html.text(store.unix_seconds_to_rfc3339(revision.edited_at)),
              ]),
              html.text(" " <> revision.body),
            ])
          }),
        ),
      ])
  }
}

fn view_create(model: Model) -> Element(Message) {
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

fn view_edit(model: Model, id: Int) -> Element(Message) {
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

fn view_confirm_delete(model: Model, id: Int) -> Element(Message) {
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

fn key_value_row(key: String, value: String) -> Element(Message) {
  html.tr([], [
    html.th([], [html.text(key)]),
    html.td([], [html.text(value)]),
  ])
}

fn view_status(model: Model) -> Element(Message) {
  case model.status {
    NoStatus -> element.none()
    Success(message) ->
      html.div([attribute.class("status success")], [html.text(message)])
    Failure(message) ->
      html.div([attribute.class("status error")], [html.text(message)])
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
