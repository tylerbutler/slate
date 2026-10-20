import dotes/request
import dotes/store
import dotes/tui
import dotes/web
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import lustre/effect
import lustre/element
import simplifile
import slate
import slate/bag
import slate/duplicate_bag
import terminal_render_test_helper
import unitest

pub fn main() -> Nil {
  unitest.main()
}

pub fn tui_async_success_test() -> Nil {
  use store <- with_store
  let #(initial, _) = tui.init(store)
  let #(editing, _) = tui.update(initial, tui.GoToEdit(1))
  let #(editing, _) = tui.update(editing, tui.BodyChanged("edited"))
  let assert #(editing, [save]) = tui.update(editing, tui.SubmitEdit(1))
  let completion = save()
  assert completion == tui.NoteUpdated(editing.request, 1, Ok(Nil))
  let #(detail, commands) = tui.update(editing, completion)
  assert detail.screen == tui.NoteDetail(1)
  assert detail.status == tui.Success("Note updated")
  let assert [load] = commands
  let assert #(loaded, []) = tui.update(detail, load())
  let assert Ok(note) = loaded.detail_note
  assert note.body == "edited"
  let #(tagging, _) = tui.update(loaded, tui.TagChanged("tag"))
  let assert #(tagging, [toggle]) = tui.update(tagging, tui.SubmitToggleTag(1))
  assert toggle() == tui.TagToggled(tagging.request, 1, Ok(True))
  let assert #(tagged, [refresh]) =
    tui.update(tagging, tui.TagToggled(tagging.request, 1, Ok(True)))
  assert tagged.tag_input == ""
  assert tagged.status == tui.Success("Tag added")
  let #(refreshed, _) = tui.update(tagged, refresh())
  assert refreshed.detail_tags == Ok(["tag"])
  let assert #(edit_error, []) =
    tui.update(
      editing,
      tui.NoteUpdated(editing.request, 1, Error("save failed")),
    )
  assert edit_error.screen == tui.NoteEdit(1)
  assert edit_error.status == tui.Failure("save failed")
  let assert #(tag_error, []) =
    tui.update(tagging, tui.TagToggled(tagging.request, 1, Error("tag failed")))
  assert tag_error.tag_input == "tag"
  assert tag_error.status == tui.Failure("tag failed")
  let #(list, _) = tui.update(tag_error, tui.GoToList)
  assert list.status == tui.NoStatus
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
      let current =
        tui.Model(
          ..initial,
          screen:,
          tag_input: "keep",
          request: request.navigate(initial.request),
        )
      list.each(
        [
          tui.NoteUpdated(initial.request, 1, Ok(Nil)),
          tui.NoteUpdated(initial.request, 1, Error("late")),
          tui.TagToggled(initial.request, 1, Ok(True)),
          tui.TagToggled(initial.request, 1, Error("late")),
          tui.NoteDetailLoaded(
            initial.request,
            1,
            Ok(store.Detail(note, Ok([]), Ok([]))),
          ),
          tui.NoteDetailLoaded(initial.request, 1, Error("late")),
          tui.NoteCreated(initial.request, Ok(2)),
          tui.NoteCreated(initial.request, Error("late")),
          tui.NoteDeleted(initial.request, Ok(Nil)),
          tui.NoteDeleted(initial.request, Error("late")),
          tui.NotesLoaded(initial.request, Ok([])),
          tui.NotesLoaded(initial.request, Error("late")),
        ],
        fn(message) {
          let #(updated, commands) = tui.update(current, message)
          assert updated == current
          assert commands == []
        },
      )
    },
  )
  let previous =
    tui.Model(..initial, detail_note: Ok(note), detail_tags: Ok(["old"]))
  let #(loading, _) = tui.update(previous, tui.GoToDetail(2))
  assert loading.detail_note == Error(Nil)
  assert loading.detail_tags == Ok([])
  let #(failed, _) =
    tui.update(
      loading,
      tui.NoteDetailLoaded(loading.request, 2, Error("missing")),
    )
  assert failed.screen == tui.NoteList
  assert failed.status == tui.Failure("missing")
  let #(detail, _) = tui.update(initial, tui.GoToDetail(1))
  let #(unchanged, _) =
    tui.update(detail, tui.NoteUpdated(initial.request, 1, Ok(Nil)))
  assert unchanged == detail
  let #(editing, _) = tui.update(initial, tui.GoToEdit(1))
  let #(unchanged, _) =
    tui.update(editing, tui.TagToggled(initial.request, 1, Ok(True)))
  assert unchanged == editing
  let #(unchanged, _) =
    tui.update(
      editing,
      tui.NoteDetailLoaded(
        initial.request,
        1,
        Ok(store.Detail(note, Ok([]), Ok([]))),
      ),
    )
  assert unchanged == editing
}

pub fn web_async_success_test() -> Nil {
  use store <- with_store
  let #(initial, _) = web.init(store)
  let #(editing, _) = web.update(initial, web.GoToEdit(1))
  let #(editing, _) = web.update(editing, web.BodyChanged("edited"))
  let #(editing, save) = web.update(editing, web.SubmitEdit(1))
  let assert Ok(completion) = run_effect(save)
  assert completion == web.NoteUpdated(editing.request, 1, Ok(Nil))
  let #(detail, load) = web.update(editing, completion)
  assert detail.screen == web.NoteDetail(1)
  assert detail.status == web.Success("Note updated")
  let assert Ok(completion) = run_effect(load)
  let #(loaded, _) = web.update(detail, completion)
  let assert Ok(note) = loaded.detail_note
  assert note.body == "edited"
  let #(tagging, _) = web.update(loaded, web.TagChanged("tag"))
  let #(tagging, toggle) = web.update(tagging, web.SubmitToggleTag(1))
  assert run_effect(toggle) == Ok(web.TagToggled(tagging.request, 1, Ok(True)))
  let #(tagged, refresh) =
    web.update(tagging, web.TagToggled(tagging.request, 1, Ok(True)))
  assert tagged.tag_input == ""
  assert tagged.status == web.Success("Tag added")
  let assert Ok(completion) = run_effect(refresh)
  let #(refreshed, _) = web.update(tagged, completion)
  assert refreshed.detail_tags == Ok(["tag"])
  let #(edit_error, effect) =
    web.update(
      editing,
      web.NoteUpdated(editing.request, 1, Error("save failed")),
    )
  assert edit_error.screen == web.NoteEdit(1)
  assert edit_error.status == web.Failure("save failed")
  assert run_effect(effect) == Error(Nil)
  let #(tag_error, effect) =
    web.update(tagging, web.TagToggled(tagging.request, 1, Error("tag failed")))
  assert tag_error.tag_input == "tag"
  assert tag_error.status == web.Failure("tag failed")
  assert run_effect(effect) == Error(Nil)
  let #(list, _) = web.update(tag_error, web.GoToList)
  assert list.status == web.NoStatus
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
      let current =
        web.Model(
          ..initial,
          screen:,
          tag_input: "keep",
          request: request.navigate(initial.request),
        )
      list.each(
        [
          web.NoteUpdated(initial.request, 1, Ok(Nil)),
          web.NoteUpdated(initial.request, 1, Error("late")),
          web.TagToggled(initial.request, 1, Ok(True)),
          web.TagToggled(initial.request, 1, Error("late")),
          web.NoteDetailLoaded(
            initial.request,
            1,
            Ok(store.Detail(note, Ok([]), Ok([]))),
          ),
          web.NoteDetailLoaded(initial.request, 1, Error("late")),
          web.NoteCreated(initial.request, Ok(2)),
          web.NoteCreated(initial.request, Error("late")),
          web.NoteDeleted(initial.request, Ok(Nil)),
          web.NoteDeleted(initial.request, Error("late")),
          web.NotesLoaded(initial.request, Ok([])),
          web.NotesLoaded(initial.request, Error("late")),
        ],
        fn(message) {
          let #(updated, effect) = web.update(current, message)
          assert updated == current
          assert run_effect(effect) == Error(Nil)
        },
      )
    },
  )
  let previous =
    web.Model(..initial, detail_note: Ok(note), detail_tags: Ok(["old"]))
  let #(loading, _) = web.update(previous, web.GoToDetail(2))
  assert loading.detail_note == Error(Nil)
  assert loading.detail_tags == Ok([])
  let #(failed, _) =
    web.update(
      loading,
      web.NoteDetailLoaded(loading.request, 2, Error("missing")),
    )
  assert failed.screen == web.NoteList
  assert failed.status == web.Failure("missing")
  let #(detail, _) = web.update(initial, web.GoToDetail(1))
  let #(unchanged, effect) =
    web.update(detail, web.NoteUpdated(initial.request, 1, Ok(Nil)))
  assert unchanged == detail
  assert run_effect(effect) == Error(Nil)
  let #(editing, _) = web.update(initial, web.GoToEdit(1))
  let #(unchanged, effect) =
    web.update(editing, web.TagToggled(initial.request, 1, Ok(True)))
  assert unchanged == editing
  assert run_effect(effect) == Error(Nil)
  let #(unchanged, effect) =
    web.update(
      editing,
      web.NoteDetailLoaded(
        initial.request,
        1,
        Ok(store.Detail(note, Ok([]), Ok([]))),
      ),
    )
  assert unchanged == editing
  assert run_effect(effect) == Error(Nil)
}

pub fn websocket_success_and_cleanup_test() -> Nil {
  use store <- with_store
  socket_lifecycle(store, False)
}

pub fn tui_create_draft_and_delete_navigation_test() -> Nil {
  use store <- with_store
  let #(initial, _) = tui.init(store)
  let #(creating, _) = tui.update(initial, tui.GoToCreate)
  let #(creating, _) = tui.update(creating, tui.TitleChanged("created"))
  let assert #(pending, [create]) = tui.update(creating, tui.SubmitCreate)
  let #(draft, _) = tui.update(pending, tui.BodyChanged("new draft"))
  // The storage write still runs, even though its response is obsolete.
  let created = create()
  let assert #(unchanged, []) = tui.update(draft, created)
  assert unchanged == draft
  let assert Ok(notes) = store.list_notes(store)
  assert list.length(notes) == 2
  let #(away, _) = tui.update(pending, tui.GoToList)
  let #(new_form, _) = tui.update(away, tui.GoToCreate)
  let assert #(unchanged, []) = tui.update(new_form, created)
  assert unchanged == new_form
  let #(confirmed, _) = tui.update(initial, tui.AskDelete(1))
  let assert #(pending, [delete]) =
    tui.update(confirmed, tui.ConfirmDeleteNote(1))
  let #(later, _) = tui.update(pending, tui.GoToCreate)
  let deleted = delete()
  let assert #(unchanged, []) = tui.update(later, deleted)
  assert unchanged == later
  assert store.get_note(store, 1) == Error(store.Storage(slate.NotFound))
  let #(accepted, _) = tui.update(pending, deleted)
  assert accepted.screen == tui.NoteList
  assert accepted.status == tui.Success("Note deleted")
}

pub fn web_create_draft_and_delete_navigation_test() -> Nil {
  use store <- with_store
  let #(initial, _) = web.init(store)
  let #(creating, _) = web.update(initial, web.GoToCreate)
  let #(creating, _) = web.update(creating, web.TitleChanged("created"))
  let #(pending, create) = web.update(creating, web.SubmitCreate)
  let #(draft, _) = web.update(pending, web.BodyChanged("new draft"))
  let assert Ok(created) = run_effect(create)
  let #(unchanged, ignored) = web.update(draft, created)
  assert unchanged == draft
  assert run_effect(ignored) == Error(Nil)
  let assert Ok(notes) = store.list_notes(store)
  assert list.length(notes) == 2
  let #(away, _) = web.update(pending, web.GoToList)
  let #(new_form, _) = web.update(away, web.GoToCreate)
  let #(unchanged, ignored) = web.update(new_form, created)
  assert unchanged == new_form
  assert run_effect(ignored) == Error(Nil)
  let #(confirmed, _) = web.update(initial, web.AskDelete(1))
  let #(pending, delete) = web.update(confirmed, web.ConfirmDeleteNote(1))
  let #(later, _) = web.update(pending, web.GoToCreate)
  let assert Ok(deleted) = run_effect(delete)
  let #(unchanged, ignored) = web.update(later, deleted)
  assert unchanged == later
  assert run_effect(ignored) == Error(Nil)
  assert store.get_note(store, 1) == Error(store.Storage(slate.NotFound))
  let #(accepted, _) = web.update(pending, deleted)
  assert accepted.screen == web.NoteList
  assert accepted.status == web.Success("Note deleted")
}

pub fn tui_same_note_revisit_and_form_revision_test() -> Nil {
  use store <- with_store
  let #(initial, _) = tui.init(store)
  let #(editing, _) = tui.update(initial, tui.GoToEdit(1))
  let assert #(pending, [save]) = tui.update(editing, tui.SubmitEdit(1))
  let saved = save()
  let #(revised, _) = tui.update(pending, tui.BodyChanged("keep draft"))
  let #(newer, _) = tui.update(pending, tui.SubmitEdit(1))
  let #(away, _) = tui.update(pending, tui.GoToList)
  let #(revisited, _) = tui.update(away, tui.GoToEdit(1))
  list.each([revised, newer, revisited], fn(current) {
    let assert #(unchanged, []) = tui.update(current, saved)
    assert unchanged == current
  })
  let #(detail, _) = tui.update(initial, tui.GoToDetail(1))
  let #(tagging, _) = tui.update(detail, tui.TagChanged("tag"))
  let assert #(pending, [toggle]) = tui.update(tagging, tui.SubmitToggleTag(1))
  let toggled = toggle()
  let #(revised, _) = tui.update(pending, tui.TagChanged("keep tag"))
  let #(newer, _) = tui.update(pending, tui.SubmitToggleTag(1))
  let #(away, _) = tui.update(pending, tui.GoToList)
  let #(revisited, _) = tui.update(away, tui.GoToDetail(1))
  list.each([revised, newer, revisited], fn(current) {
    let assert #(unchanged, []) = tui.update(current, toggled)
    assert unchanged == current
  })
}

pub fn web_same_note_revisit_and_form_revision_test() -> Nil {
  use store <- with_store
  let #(initial, _) = web.init(store)
  let #(editing, _) = web.update(initial, web.GoToEdit(1))
  let #(pending, save) = web.update(editing, web.SubmitEdit(1))
  let assert Ok(saved) = run_effect(save)
  let #(revised, _) = web.update(pending, web.BodyChanged("keep draft"))
  let #(newer, _) = web.update(pending, web.SubmitEdit(1))
  let #(away, _) = web.update(pending, web.GoToList)
  let #(revisited, _) = web.update(away, web.GoToEdit(1))
  list.each([revised, newer, revisited], fn(current) {
    let #(unchanged, ignored) = web.update(current, saved)
    assert unchanged == current
    assert run_effect(ignored) == Error(Nil)
  })
  let #(detail, _) = web.update(initial, web.GoToDetail(1))
  let #(tagging, _) = web.update(detail, web.TagChanged("tag"))
  let #(pending, toggle) = web.update(tagging, web.SubmitToggleTag(1))
  let assert Ok(toggled) = run_effect(toggle)
  let #(revised, _) = web.update(pending, web.TagChanged("keep tag"))
  let #(newer, _) = web.update(pending, web.SubmitToggleTag(1))
  let #(away, _) = web.update(pending, web.GoToList)
  let #(revisited, _) = web.update(away, web.GoToDetail(1))
  list.each([revised, newer, revisited], fn(current) {
    let #(unchanged, ignored) = web.update(current, toggled)
    assert unchanged == current
    assert run_effect(ignored) == Error(Nil)
  })
}

pub fn tui_out_of_order_load_and_submission_test() -> Nil {
  use store <- with_store
  let assert #(initial, [old_list]) = tui.init(store)
  let old_list_result = old_list()
  let #(first, _) = tui.update(initial, tui.GoToCreate)
  let #(first, _) = tui.update(first, tui.TitleChanged("new note"))
  let assert #(first, [old_create]) = tui.update(first, tui.SubmitCreate)
  let assert #(second, [new_create]) = tui.update(first, tui.SubmitCreate)
  let old_result = old_create()
  let assert #(unchanged, []) = tui.update(second, old_result)
  assert unchanged == second
  let assert #(listing, [new_list]) = tui.update(second, new_create())
  assert listing.screen == tui.NoteList
  let #(loaded, _) = tui.update(listing, new_list())
  assert list.length(loaded.notes) == 3
  let assert #(unchanged, []) = tui.update(loaded, old_list_result)
  assert unchanged == loaded
  let assert #(first, [old_detail]) = tui.update(loaded, tui.GoToDetail(1))
  let old_detail_result = old_detail()
  let assert Ok(Nil) = store.update_note(store, 1, "newest body")
  let #(away, _) = tui.update(first, tui.GoToList)
  let assert #(second, [new_detail]) = tui.update(away, tui.GoToDetail(1))
  let assert #(unchanged, []) = tui.update(second, old_detail_result)
  assert unchanged == second
  let #(loaded, _) = tui.update(second, new_detail())
  let assert Ok(note) = loaded.detail_note
  assert note.body == "newest body"
  let assert #(unchanged, []) = tui.update(loaded, old_detail_result)
  assert unchanged == loaded
}

pub fn web_out_of_order_load_and_submission_test() -> Nil {
  use store <- with_store
  let #(initial, old_list) = web.init(store)
  let assert Ok(old_list_result) = run_effect(old_list)
  let #(first, _) = web.update(initial, web.GoToCreate)
  let #(first, _) = web.update(first, web.TitleChanged("new note"))
  let #(first, old_create) = web.update(first, web.SubmitCreate)
  let #(second, new_create) = web.update(first, web.SubmitCreate)
  let assert Ok(old_result) = run_effect(old_create)
  let #(unchanged, ignored) = web.update(second, old_result)
  assert unchanged == second
  assert run_effect(ignored) == Error(Nil)
  let assert Ok(new_result) = run_effect(new_create)
  let #(listing, new_list) = web.update(second, new_result)
  assert listing.screen == web.NoteList
  let assert Ok(completion) = run_effect(new_list)
  let #(loaded, _) = web.update(listing, completion)
  assert list.length(loaded.notes) == 3
  let #(unchanged, ignored) = web.update(loaded, old_list_result)
  assert unchanged == loaded
  assert run_effect(ignored) == Error(Nil)
  let #(first, old_detail) = web.update(loaded, web.GoToDetail(1))
  let assert Ok(old_result) = run_effect(old_detail)
  let assert Ok(Nil) = store.update_note(store, 1, "newest body")
  let #(away, _) = web.update(first, web.GoToList)
  let #(second, new_detail) = web.update(away, web.GoToDetail(1))
  let #(unchanged, ignored) = web.update(second, old_result)
  assert unchanged == second
  assert run_effect(ignored) == Error(Nil)
  let assert Ok(completion) = run_effect(new_detail)
  let #(loaded, _) = web.update(second, completion)
  let assert Ok(note) = loaded.detail_note
  assert note.body == "newest body"
  let #(unchanged, ignored) = web.update(loaded, old_result)
  assert unchanged == loaded
  assert run_effect(ignored) == Error(Nil)
}

pub fn detail_tag_decode_failure_test() -> Nil {
  with_partial_store(True, False, fn(store) {
    let assert Ok(detail) = store.get_detail(store, 1)
    assert detail.note.body == "readable"
    let assert Error(store.Storage(slate.DecodeErrors(_))) = detail.tags
    let assert Ok([revision]) = detail.history
    assert revision.body == "original"
    assert_partial_views(store, "Tags unavailable:", "original")
  })
}

pub fn terminal_render_timeout_cleanup_test() -> Nil {
  use store <- with_store
  let caller = process.self()
  let #(initial, _) = tui.init(store)
  let assert #(loading, [load]) = tui.update(initial, tui.GoToDetail(1))
  let #(loaded, _) = tui.update(loading, load())
  let sentinel = process.new_subject()
  process.send(sentinel, "keep caller message")
  let unrelated = process.spawn(fn() { process.sleep_forever() })
  let unrelated_monitor = process.monitor(unrelated)
  // A bounded first-view block hits Shore's real one-second InitTimeout.
  let #(timed_out, cleanup) =
    terminal_render_test_helper.try_render(loaded, fn() {
      process.sleep_forever()
    })
  let cleaned = terminal_render_test_helper.is_clean(cleanup)
  let untouched = process.is_alive(unrelated)
  process.unlink(unrelated)
  process.kill(unrelated)
  let unrelated_down =
    process.new_selector()
    |> process.select_specific_monitor(unrelated_monitor, fn(down) { down })
    |> process.selector_receive(1000)
  process.demonitor_process(unrelated_monitor)
  let assert Error(terminal_render_test_helper.RenderError(
    Some(terminal_render_test_helper.StartFailed("InitTimeout")),
    [],
  )) = timed_out
  assert cleaned
  assert untouched
  let assert Ok(_) = unrelated_down
  assert process.receive(sentinel, 0) == Ok("keep caller message")
  assert process.self() == caller
  assert terminal_render_test_helper.discarded_frames(cleanup) != []
  let #(rendered, cleanup) =
    terminal_render_test_helper.try_render(loaded, fn() { Nil })
  let assert Ok(output) = rendered
  assert string.contains(output, "original")
  assert terminal_render_test_helper.is_clean(cleanup)
  assert process.self() == caller
}

pub fn tui_same_value_callbacks_keep_submissions_test() -> Nil {
  use store <- with_store
  let #(initial, _) = tui.init(store)
  let #(creating, _) = tui.update(initial, tui.GoToCreate)
  let #(creating, _) = tui.update(creating, tui.TitleChanged("title"))
  let #(creating, _) = tui.update(creating, tui.BodyChanged("body"))
  let assert #(pending, [create]) = tui.update(creating, tui.SubmitCreate)
  let assert #(focused, []) = tui.update(pending, tui.TitleChanged("title"))
  let assert #(focused, []) = tui.update(focused, tui.BodyChanged("body"))
  assert focused == pending
  let #(created, _) = tui.update(focused, create())
  assert created.screen == tui.NoteList
  assert created.status == tui.Success("Created note #2")
  let assert #(failed, []) =
    tui.update(
      focused,
      tui.NoteCreated(pending.request, Error("create failed")),
    )
  assert failed.screen == tui.NoteCreate
  assert failed.status == tui.Failure("create failed")
  let #(editing, _) = tui.update(initial, tui.GoToEdit(1))
  let #(editing, _) = tui.update(editing, tui.BodyChanged("edited"))
  let assert #(pending, [save]) = tui.update(editing, tui.SubmitEdit(1))
  let assert #(focused, []) = tui.update(pending, tui.BodyChanged("edited"))
  assert focused == pending
  let saved = save()
  let #(updated, _) = tui.update(focused, saved)
  assert updated.screen == tui.NoteDetail(1)
  assert updated.status == tui.Success("Note updated")
  let assert #(failed, []) =
    tui.update(
      focused,
      tui.NoteUpdated(pending.request, 1, Error("save failed")),
    )
  assert failed.screen == tui.NoteEdit(1)
  assert failed.status == tui.Failure("save failed")
  let #(revised, _) = tui.update(focused, tui.BodyChanged("real edit"))
  let assert #(unchanged, []) = tui.update(revised, saved)
  assert unchanged == revised
  let assert #(unchanged, []) =
    tui.update(revised, tui.NoteUpdated(pending.request, 1, Error("late")))
  assert unchanged == revised
}

pub fn web_same_value_callbacks_keep_submissions_test() -> Nil {
  use store <- with_store
  let #(initial, _) = web.init(store)
  let #(creating, _) = web.update(initial, web.GoToCreate)
  let #(creating, _) = web.update(creating, web.TitleChanged("title"))
  let #(creating, _) = web.update(creating, web.BodyChanged("body"))
  let #(pending, create) = web.update(creating, web.SubmitCreate)
  let #(focused, ignored) = web.update(pending, web.TitleChanged("title"))
  assert run_effect(ignored) == Error(Nil)
  let #(focused, ignored) = web.update(focused, web.BodyChanged("body"))
  assert run_effect(ignored) == Error(Nil)
  assert focused == pending
  let assert Ok(created) = run_effect(create)
  let #(created, _) = web.update(focused, created)
  assert created.screen == web.NoteList
  assert created.status == web.Success("Created note #2")
  let #(failed, ignored) =
    web.update(
      focused,
      web.NoteCreated(pending.request, Error("create failed")),
    )
  assert run_effect(ignored) == Error(Nil)
  assert failed.screen == web.NoteCreate
  assert failed.status == web.Failure("create failed")
  let #(editing, _) = web.update(initial, web.GoToEdit(1))
  let #(editing, _) = web.update(editing, web.BodyChanged("edited"))
  let #(pending, save) = web.update(editing, web.SubmitEdit(1))
  let #(focused, ignored) = web.update(pending, web.BodyChanged("edited"))
  assert run_effect(ignored) == Error(Nil)
  assert focused == pending
  let assert Ok(saved) = run_effect(save)
  let #(updated, _) = web.update(focused, saved)
  assert updated.screen == web.NoteDetail(1)
  assert updated.status == web.Success("Note updated")
  let #(failed, ignored) =
    web.update(
      focused,
      web.NoteUpdated(pending.request, 1, Error("save failed")),
    )
  assert run_effect(ignored) == Error(Nil)
  assert failed.screen == web.NoteEdit(1)
  assert failed.status == web.Failure("save failed")
  let #(revised, _) = web.update(focused, web.BodyChanged("real edit"))
  let #(unchanged, ignored) = web.update(revised, saved)
  assert unchanged == revised
  assert run_effect(ignored) == Error(Nil)
  let #(unchanged, ignored) =
    web.update(revised, web.NoteUpdated(pending.request, 1, Error("late")))
  assert unchanged == revised
  assert run_effect(ignored) == Error(Nil)
}

pub fn tui_tag_draft_replaces_pending_refresh_test() -> Nil {
  with_store(assert_tui_tag_refresh(_, False))
  with_partial_store(False, True, assert_tui_tag_refresh(_, True))
}

fn assert_tui_tag_refresh(store: store.Store, history_fails: Bool) -> Nil {
  let #(initial, _) = tui.init(store)
  let assert #(loading, [load]) = tui.update(initial, tui.GoToDetail(1))
  let #(loaded, _) = tui.update(loading, load())
  let assert #(tagging, []) = tui.update(loaded, tui.TagChanged("added"))
  let assert #(pending, [toggle]) = tui.update(tagging, tui.SubmitToggleTag(1))
  let assert #(focused, []) = tui.update(pending, tui.TagChanged("added"))
  assert focused == pending
  let assert #(tagged, [old_refresh]) = tui.update(focused, toggle())
  assert tagged.detail_loading
  assert tagged.tag_input == ""
  let assert #(unchanged, []) = tui.update(tagged, tui.SubmitToggleTag(1))
  assert unchanged == tagged
  let assert #(draft, [refresh]) =
    tui.update(tagged, tui.TagChanged("next draft"))
  let assert #(focused, []) = tui.update(draft, tui.TagChanged("next draft"))
  assert focused == draft
  let old_result = old_refresh()
  let assert #(unchanged, []) = tui.update(draft, old_result)
  assert unchanged == draft
  let #(new_submission, _) = tui.update(draft, tui.SubmitToggleTag(1))
  let assert #(failed, [recover]) =
    tui.update(
      new_submission,
      tui.TagToggled(new_submission.request, 1, Error("tag failed")),
    )
  let assert #(recovered, []) = tui.update(failed, recover())
  assert recovered.status == tui.Failure("tag failed")
  assert recovered.tag_input == "next draft"
  let assert Ok(recovered_tags) = recovered.detail_tags
  assert list.contains(recovered_tags, "added")
  let assert #(refreshed, []) = tui.update(draft, refresh())
  assert !refreshed.detail_loading
  assert refreshed.tag_input == "next draft"
  assert refreshed.status == tui.Success("Tag added")
  let assert Ok(tags) = refreshed.detail_tags
  assert list.contains(tags, "added")
  case history_fails {
    True -> {
      let assert Error(store.Storage(slate.DecodeErrors(_))) =
        refreshed.detail_history
      let terminal = terminal_render_test_helper.render(refreshed)
      assert string.contains(terminal, "readable")
      assert string.contains(terminal, "added")
      assert string.contains(terminal, "History unavailable:")
      Nil
    }
    False -> {
      assert refreshed.detail_history == Ok([])
    }
  }
  let assert #(unchanged, []) = tui.update(refreshed, old_result)
  assert unchanged == refreshed
  let assert #(next_draft, []) =
    tui.update(refreshed, tui.TagChanged("later draft"))
  assert !next_draft.detail_loading
}

pub fn web_tag_draft_replaces_pending_refresh_test() -> Nil {
  with_store(assert_web_tag_refresh(_, False))
  with_partial_store(False, True, assert_web_tag_refresh(_, True))
}

fn assert_web_tag_refresh(store: store.Store, history_fails: Bool) -> Nil {
  let #(initial, _) = web.init(store)
  let #(loading, load) = web.update(initial, web.GoToDetail(1))
  let assert Ok(completion) = run_effect(load)
  let #(loaded, _) = web.update(loading, completion)
  let #(tagging, ignored) = web.update(loaded, web.TagChanged("added"))
  assert run_effect(ignored) == Error(Nil)
  let #(pending, toggle) = web.update(tagging, web.SubmitToggleTag(1))
  let #(focused, ignored) = web.update(pending, web.TagChanged("added"))
  assert run_effect(ignored) == Error(Nil)
  assert focused == pending
  let assert Ok(completion) = run_effect(toggle)
  let #(tagged, old_refresh) = web.update(focused, completion)
  assert tagged.detail_loading
  assert tagged.tag_input == ""
  let #(unchanged, ignored) = web.update(tagged, web.SubmitToggleTag(1))
  assert unchanged == tagged
  assert run_effect(ignored) == Error(Nil)
  let #(draft, refresh) = web.update(tagged, web.TagChanged("next draft"))
  let #(focused, ignored) = web.update(draft, web.TagChanged("next draft"))
  assert focused == draft
  assert run_effect(ignored) == Error(Nil)
  let assert Ok(old_result) = run_effect(old_refresh)
  let #(unchanged, ignored) = web.update(draft, old_result)
  assert unchanged == draft
  assert run_effect(ignored) == Error(Nil)
  let #(new_submission, _) = web.update(draft, web.SubmitToggleTag(1))
  let #(failed, recover) =
    web.update(
      new_submission,
      web.TagToggled(new_submission.request, 1, Error("tag failed")),
    )
  let assert Ok(completion) = run_effect(recover)
  let #(recovered, _) = web.update(failed, completion)
  assert recovered.status == web.Failure("tag failed")
  assert recovered.tag_input == "next draft"
  let assert Ok(recovered_tags) = recovered.detail_tags
  assert list.contains(recovered_tags, "added")
  let assert Ok(completion) = run_effect(refresh)
  let #(refreshed, ignored) = web.update(draft, completion)
  assert run_effect(ignored) == Error(Nil)
  assert !refreshed.detail_loading
  assert refreshed.tag_input == "next draft"
  assert refreshed.status == web.Success("Tag added")
  let assert Ok(tags) = refreshed.detail_tags
  assert list.contains(tags, "added")
  case history_fails {
    True -> {
      let assert Error(store.Storage(slate.DecodeErrors(_))) =
        refreshed.detail_history
      let browser = web.view(refreshed) |> element.to_string
      assert string.contains(browser, "readable")
      assert string.contains(browser, "added")
      assert string.contains(browser, "History unavailable:")
      Nil
    }
    False -> {
      assert refreshed.detail_history == Ok([])
    }
  }
  let #(unchanged, ignored) = web.update(refreshed, old_result)
  assert unchanged == refreshed
  assert run_effect(ignored) == Error(Nil)
  let #(next_draft, ignored) =
    web.update(refreshed, web.TagChanged("later draft"))
  assert !next_draft.detail_loading
  assert run_effect(ignored) == Error(Nil)
}

pub fn tui_cancel_delete_replaces_list_refresh_test() -> Nil {
  use store <- with_store
  let assert #(initial, [load]) = tui.init(store)
  let #(listing, _) = tui.update(initial, load())
  let #(creating, _) = tui.update(listing, tui.GoToCreate)
  let assert #(pending, [create]) = tui.update(creating, tui.SubmitCreate)
  let assert #(created, [old_refresh]) = tui.update(pending, create())
  assert list.length(created.notes) == 1
  let old_result = old_refresh()
  let #(confirming, _) = tui.update(created, tui.AskDelete(1))
  let assert #(cancelled, [refresh]) = tui.update(confirming, tui.CancelDelete)
  let assert #(unchanged, []) = tui.update(cancelled, old_result)
  assert unchanged == cancelled
  let current_result = refresh()
  let assert #(restored, []) = tui.update(cancelled, current_result)
  assert restored.screen == tui.NoteList
  assert list.length(restored.notes) == 2
  list.each([old_result, current_result], fn(completion) {
    let assert #(unchanged, []) = tui.update(restored, completion)
    assert unchanged == restored
  })
}

pub fn web_cancel_delete_replaces_list_refresh_test() -> Nil {
  use store <- with_store
  let #(initial, load) = web.init(store)
  let assert Ok(completion) = run_effect(load)
  let #(listing, _) = web.update(initial, completion)
  let #(creating, _) = web.update(listing, web.GoToCreate)
  let #(pending, create) = web.update(creating, web.SubmitCreate)
  let assert Ok(completion) = run_effect(create)
  let #(created, old_refresh) = web.update(pending, completion)
  assert list.length(created.notes) == 1
  let assert Ok(old_result) = run_effect(old_refresh)
  let #(confirming, _) = web.update(created, web.AskDelete(1))
  let #(cancelled, refresh) = web.update(confirming, web.CancelDelete)
  let #(unchanged, ignored) = web.update(cancelled, old_result)
  assert unchanged == cancelled
  assert run_effect(ignored) == Error(Nil)
  let assert Ok(current_result) = run_effect(refresh)
  let #(restored, ignored) = web.update(cancelled, current_result)
  assert run_effect(ignored) == Error(Nil)
  assert restored.screen == web.NoteList
  assert list.length(restored.notes) == 2
  list.each([old_result, current_result], fn(completion) {
    let #(unchanged, ignored) = web.update(restored, completion)
    assert unchanged == restored
    assert run_effect(ignored) == Error(Nil)
  })
}

pub fn detail_history_decode_failure_test() -> Nil {
  with_partial_store(False, True, fn(store) {
    let assert Ok(detail) = store.get_detail(store, 1)
    assert detail.note.body == "readable"
    assert detail.tags == Ok(["valid tag"])
    let assert Error(store.Storage(slate.DecodeErrors(_))) = detail.history
    assert_partial_views(store, "History unavailable:", "valid tag")
  })
}

pub fn detail_both_sections_fail_and_missing_note_test() -> Nil {
  with_partial_store(True, True, fn(store) {
    let assert Ok(detail) = store.get_detail(store, 1)
    assert detail.note.body == "readable"
    let assert Error(store.Storage(slate.DecodeErrors(_))) = detail.tags
    let assert Error(store.Storage(slate.DecodeErrors(_))) = detail.history
    assert store.get_detail(store, 999) == Error(store.Storage(slate.NotFound))
    assert_partial_views(store, "Tags unavailable:", "History unavailable:")
  })
}

fn assert_partial_views(
  store: store.Store,
  failure: String,
  successful: String,
) -> Nil {
  let #(initial, _) = tui.init(store)
  let assert #(loading, [load]) = tui.update(initial, tui.GoToDetail(1))
  let #(loaded, _) = tui.update(loading, load())
  let assert Ok(note) = loaded.detail_note
  assert note.body == "readable"
  let terminal = terminal_render_test_helper.render(loaded)
  assert string.contains(terminal, "readable")
  assert string.contains(terminal, failure)
  assert string.contains(terminal, successful)
  let #(initial, _) = web.init(store)
  let #(loading, load) = web.update(initial, web.GoToDetail(1))
  let assert Ok(completion) = run_effect(load)
  let #(loaded, _) = web.update(loading, completion)
  let browser = web.view(loaded) |> element.to_string
  assert string.contains(browser, "readable")
  assert string.contains(browser, failure)
  assert string.contains(browser, successful)
}

fn with_partial_store(
  bad_tags: Bool,
  bad_history: Bool,
  run: fn(store.Store) -> Nil,
) -> Nil {
  let path = "build/dotes-partial-" <> int.to_string(unique_integer())
  let assert Ok(store) = store.open_in(path)
  let assert Ok(1) = store.create_note(store, "one", "original")
  let assert Ok(Nil) = store.update_note(store, 1, "readable")
  let assert Ok(True) = store.toggle_tag(store, 1, "valid tag")
  let assert Ok(Nil) = store.close(store)
  // Seed valid DETS files with incompatible values only while the store is closed.
  case bad_tags {
    False -> Nil
    True -> {
      let assert Ok(tags) =
        bag.open(path <> "/tags.dets", decode.int, decode.int)
      let assert Ok(Nil) = bag.insert(tags, 1, 42)
      let assert Ok(Nil) = bag.close(tags)
      Nil
    }
  }
  case bad_history {
    False -> Nil
    True -> {
      let assert Ok(history) =
        duplicate_bag.open(path <> "/history.dets", decode.int, decode.string)
      let assert Ok(Nil) = duplicate_bag.insert(history, 1, "not a revision")
      let assert Ok(Nil) = duplicate_bag.close(history)
      Nil
    }
  }
  let assert Ok(reopened) = store.open_in(path)
  run(reopened)
  let assert Ok(Nil) = store.close(reopened)
  let assert Ok(Nil) = simplifile.delete(path)
  Nil
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
  let assert Ok(store) = store.open_in(path)
  let assert Ok(1) = store.create_note(store, "one", "original")
  run(store)
  let assert Ok(Nil) = store.close(store)
  // All sessions have confirmed cleanup; only now remove the test directory.
  let assert Ok(Nil) = simplifile.delete(path)
  Nil
}

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

@external(erlang, "dotes_test_ffi", "socket_lifecycle")
fn socket_lifecycle(store: store.Store, fail_send: Bool) -> Nil

@external(erlang, "dotes_test_ffi", "socket_init_failure")
fn socket_init_failure() -> Nil

@external(erlang, "dotes_test_ffi", "runtime_file_responses")
fn runtime_file_responses() -> Nil
