import dotes/store
import dotes_tui as tui
import dotes_web as web
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import lustre/effect
import simplifile
import slate/bag
import slate/duplicate_bag
import slate/set
import startest
import startest/expect

pub fn main() -> Nil {
  startest.run(startest.default_config())
}

pub fn tui_async_success_test() -> Nil {
  use store <- with_store
  let #(initial, _) = tui.init(store)
  let #(editing, _) = tui.update(initial, tui.GoToEdit(1))
  let #(editing, _) = tui.update(editing, tui.BodyChanged("edited"))
  let assert #(_, [save]) = tui.update(editing, tui.SubmitEdit(1))
  let completion = save()
  completion |> expect.to_equal(tui.NoteUpdated(1, Ok(Nil)))
  let #(detail, commands) = tui.update(editing, completion)
  detail.screen |> expect.to_equal(tui.NoteDetail(1))
  let assert [load] = commands
  let assert #(loaded, []) = tui.update(detail, load())
  let assert Ok(note) = loaded.detail_note
  note.body |> expect.to_equal("edited")
  let #(tagging, _) = tui.update(loaded, tui.TagChanged("tag"))
  let assert #(_, [toggle]) = tui.update(tagging, tui.SubmitToggleTag(1))
  toggle() |> expect.to_equal(tui.TagToggled(1, Ok(True)))
  let assert #(tagged, [refresh]) =
    tui.update(tagging, tui.TagToggled(1, Ok(True)))
  tagged.tag_input |> expect.to_equal("")
  let #(refreshed, _) = tui.update(tagged, refresh())
  refreshed.detail_tags |> expect.to_equal(["tag"])
  let assert #(edit_error, []) =
    tui.update(editing, tui.NoteUpdated(1, Error("save failed")))
  edit_error.screen |> expect.to_equal(tui.NoteEdit(1))
  edit_error.status_message |> expect.to_equal("save failed")
  let assert #(tag_error, []) =
    tui.update(tagging, tui.TagToggled(1, Error("tag failed")))
  tag_error.tag_input |> expect.to_equal("tag")
  tag_error.status_message |> expect.to_equal("tag failed")
}

pub fn tui_late_completions_test() -> Nil {
  use store <- with_store
  let #(initial, _) = tui.init(store)
  let assert Ok(note) = store.get_note(store, 1)
  list.each(
    [
      tui.NoteList,
      tui.NoteCreate,
      tui.NoteDetail(2),
      tui.NoteEdit(2),
      tui.ConfirmDelete(2),
    ],
    fn(screen) {
      let current = tui.Model(..initial, screen:, tag_input: "keep")
      list.each(
        [
          tui.NoteUpdated(1, Ok(Nil)),
          tui.NoteUpdated(1, Error("late")),
          tui.TagToggled(1, Ok(True)),
          tui.TagToggled(1, Error("late")),
          tui.NoteDetailLoaded(1, Ok(#(note, [], []))),
          tui.NoteDetailLoaded(1, Error("late")),
        ],
        fn(message) {
          let #(updated, commands) = tui.update(current, message)
          updated |> expect.to_equal(current)
          list.length(commands) |> expect.to_equal(0)
        },
      )
    },
  )
  let previous =
    tui.Model(..initial, detail_note: Ok(note), detail_tags: ["old"])
  let #(loading, _) = tui.update(previous, tui.GoToDetail(2))
  loading.detail_note |> expect.to_equal(Error(Nil))
  loading.detail_tags |> expect.to_equal([])
  let #(failed, _) =
    tui.update(loading, tui.NoteDetailLoaded(2, Error("missing")))
  failed.screen |> expect.to_equal(tui.NoteList)
  failed.status_message |> expect.to_equal("missing")
  let detail = tui.Model(..initial, screen: tui.NoteDetail(1))
  let #(unchanged, _) = tui.update(detail, tui.NoteUpdated(1, Ok(Nil)))
  unchanged |> expect.to_equal(detail)
  let editing = tui.Model(..initial, screen: tui.NoteEdit(1))
  let #(unchanged, _) = tui.update(editing, tui.TagToggled(1, Ok(True)))
  unchanged |> expect.to_equal(editing)
  let #(unchanged, _) =
    tui.update(editing, tui.NoteDetailLoaded(1, Ok(#(note, [], []))))
  unchanged |> expect.to_equal(editing)
}

pub fn web_async_success_test() -> Nil {
  use store <- with_store
  let #(initial, _) = web.init(store)
  let #(editing, _) = web.update(initial, web.GoToEdit(1))
  let #(editing, _) = web.update(editing, web.BodyChanged("edited"))
  let #(_, save) = web.update(editing, web.SubmitEdit(1))
  let assert Ok(completion) = run_effect(save)
  completion |> expect.to_equal(web.NoteUpdated(1, Ok(Nil)))
  let #(detail, load) = web.update(editing, completion)
  detail.screen |> expect.to_equal(web.NoteDetail(1))
  let assert Ok(completion) = run_effect(load)
  let #(loaded, _) = web.update(detail, completion)
  let assert Ok(note) = loaded.detail_note
  note.body |> expect.to_equal("edited")
  let #(tagging, _) = web.update(loaded, web.TagChanged("tag"))
  let #(_, toggle) = web.update(tagging, web.SubmitToggleTag(1))
  run_effect(toggle) |> expect.to_equal(Ok(web.TagToggled(1, Ok(True))))
  let #(tagged, refresh) = web.update(tagging, web.TagToggled(1, Ok(True)))
  tagged.tag_input |> expect.to_equal("")
  let assert Ok(completion) = run_effect(refresh)
  let #(refreshed, _) = web.update(tagged, completion)
  refreshed.detail_tags |> expect.to_equal(["tag"])
  let #(edit_error, effect) =
    web.update(editing, web.NoteUpdated(1, Error("save failed")))
  edit_error.screen |> expect.to_equal(web.NoteEdit(1))
  edit_error.status_message |> expect.to_equal("save failed")
  run_effect(effect) |> expect.to_equal(Error(Nil))
  let #(tag_error, effect) =
    web.update(tagging, web.TagToggled(1, Error("tag failed")))
  tag_error.tag_input |> expect.to_equal("tag")
  tag_error.status_message |> expect.to_equal("tag failed")
  run_effect(effect) |> expect.to_equal(Error(Nil))
}

pub fn web_late_completions_test() -> Nil {
  use store <- with_store
  let #(initial, _) = web.init(store)
  let assert Ok(note) = store.get_note(store, 1)
  list.each(
    [
      web.NoteList,
      web.NoteCreate,
      web.NoteDetail(2),
      web.NoteEdit(2),
      web.ConfirmDelete(2),
    ],
    fn(screen) {
      let current = web.Model(..initial, screen:, tag_input: "keep")
      list.each(
        [
          web.NoteUpdated(1, Ok(Nil)),
          web.NoteUpdated(1, Error("late")),
          web.TagToggled(1, Ok(True)),
          web.TagToggled(1, Error("late")),
          web.NoteDetailLoaded(1, Ok(#(note, [], []))),
          web.NoteDetailLoaded(1, Error("late")),
        ],
        fn(message) {
          let #(updated, effect) = web.update(current, message)
          updated |> expect.to_equal(current)
          run_effect(effect) |> expect.to_equal(Error(Nil))
        },
      )
    },
  )
  let previous =
    web.Model(..initial, detail_note: Ok(note), detail_tags: ["old"])
  let #(loading, _) = web.update(previous, web.GoToDetail(2))
  loading.detail_note |> expect.to_equal(Error(Nil))
  loading.detail_tags |> expect.to_equal([])
  let #(failed, _) =
    web.update(loading, web.NoteDetailLoaded(2, Error("missing")))
  failed.screen |> expect.to_equal(web.NoteList)
  failed.status_message |> expect.to_equal("missing")
  let detail = web.Model(..initial, screen: web.NoteDetail(1))
  let #(unchanged, effect) = web.update(detail, web.NoteUpdated(1, Ok(Nil)))
  unchanged |> expect.to_equal(detail)
  run_effect(effect) |> expect.to_equal(Error(Nil))
  let editing = web.Model(..initial, screen: web.NoteEdit(1))
  let #(unchanged, effect) = web.update(editing, web.TagToggled(1, Ok(True)))
  unchanged |> expect.to_equal(editing)
  run_effect(effect) |> expect.to_equal(Error(Nil))
  let #(unchanged, effect) =
    web.update(editing, web.NoteDetailLoaded(1, Ok(#(note, [], []))))
  unchanged |> expect.to_equal(editing)
  run_effect(effect) |> expect.to_equal(Error(Nil))
}

pub fn websocket_success_and_cleanup_test() -> Nil {
  use store <- with_store
  socket_lifecycle(store, False)
}

pub fn websocket_send_failure_cleanup_test() -> Nil {
  use store <- with_store
  socket_lifecycle(store, True)
}

pub fn websocket_init_failure_cleanup_test() -> Nil {
  socket_init_failure()
}

pub fn runtime_file_success_and_failure_test() -> Nil {
  runtime_file_responses()
}

fn run_effect(effect: effect.Effect(message)) -> Result(message, Nil) {
  let messages = process.new_subject()
  effect.perform(
    effect,
    process.send(messages, _),
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { dynamic.nil() },
    fn(_, _) { Nil },
  )
  process.receive(messages, 0)
}

fn with_store(run: fn(store.Store) -> Nil) -> Nil {
  let path = "build/dotes-test-" <> int.to_string(unique_integer())
  let assert Ok(counter) =
    set.open(path <> "-counter", decode.string, decode.int)
  let assert Ok(notes) =
    set.open(path <> "-notes", decode.int, {
      use title <- decode.field(1, decode.string)
      use body <- decode.field(2, decode.string)
      use created_at <- decode.field(3, decode.int)
      decode.success(store.Note(title:, body:, created_at:))
    })
  let assert Ok(tags) = bag.open(path <> "-tags", decode.int, decode.string)
  let assert Ok(history) =
    duplicate_bag.open(path <> "-history", decode.int, {
      use body <- decode.field(1, decode.string)
      use edited_at <- decode.field(2, decode.int)
      decode.success(store.Revision(body:, edited_at:))
    })
  let store = store.Store(counter:, notes:, tags:, history:)
  let assert Ok(1) = store.create_note(store, "one", "original")
  run(store)
  let assert Ok(Nil) = store.close(store)
  list.each(["counter", "notes", "tags", "history"], fn(table) {
    let assert Ok(Nil) = simplifile.delete(path <> "-" <> table)
  })
}

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

@external(erlang, "dotes_test_ffi", "socket_lifecycle")
fn socket_lifecycle(store: store.Store, fail_send: Bool) -> Nil

@external(erlang, "dotes_test_ffi", "socket_init_failure")
fn socket_init_failure() -> Nil

@external(erlang, "dotes_test_ffi", "runtime_file_responses")
fn runtime_file_responses() -> Nil
