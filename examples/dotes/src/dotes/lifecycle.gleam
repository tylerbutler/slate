//// Linked UI children belong to a private lifecycle process. This lets us
//// trap before startup without changing the calling process's trap flag or
//// consuming any of its unrelated exit messages.

import dotes/store
import gleam/erlang/process
import gleam/io

type Event {
  ChildStopped(process.ExitReason)
  ParentStopped
  LinkedExit(process.ExitMessage)
}

type Shutdown {
  Shutdown
}

/// Run one linked application with a store. Startup must return its main child
/// Pid or a safe display message. Return only after store cleanup has completed.
/// The caller's exit-trapping state is unchanged.
pub fn run(
  directory: String,
  start: fn(store.Store) -> Result(process.Pid, String),
) -> Nil {
  let parent = process.self()
  let completed = process.new_subject()
  let worker =
    process.spawn_unlinked(fn() {
      // Before invoking any API which can create linked children, including
      // children that fail before startup returns their Pid.
      process.trap_exits(True)
      let parent_monitor = process.monitor(parent)
      case store.open_in(directory) {
        Error(error) ->
          io.println("Error opening store: " <> store.error_message(error))
        Ok(client) -> {
          case start(client) {
            Error(message) -> io.println(message)
            Ok(child) -> wait(child, parent_monitor)
          }
          // Keep trapping throughout cleanup: another child may still be exiting.
          case store.close(client) {
            Ok(Nil) -> Nil
            Error(error) ->
              io.println("Error closing store: " <> store.error_message(error))
          }
        }
      }
      process.demonitor_process(parent_monitor)
      drain_owned_exits()
      process.send(completed, Nil)
      // A normal exit would leave linked helpers (e.g. Shore's redraw timer)
      // alive. All store cleanup is finished; propagate shutdown to these links.
      process.trap_exits(False)
      process.send_abnormal_exit(process.self(), Shutdown)
    })
  let monitor = process.monitor(worker)
  process.new_selector()
  |> process.select(completed)
  |> process.select_specific_monitor(monitor, fn(_) {
    io.println("The dotes application lifecycle stopped unexpectedly.")
  })
  |> process.selector_receive_forever
  process.demonitor_process(monitor)
}

fn wait(child: process.Pid, parent_monitor: process.Monitor) -> Nil {
  let monitor = process.monitor(child)
  let selector =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) {
      ChildStopped(down.reason)
    })
    |> process.select_specific_monitor(parent_monitor, fn(_) { ParentStopped })
    |> process.select_trapped_exits(LinkedExit)
  wait_loop(child, selector)
  process.demonitor_process(monitor)
}

fn wait_loop(child: process.Pid, selector: process.Selector(Event)) -> Nil {
  case process.selector_receive_forever(selector) {
    ChildStopped(process.Normal) -> Nil
    ChildStopped(_) -> io.println("The dotes application stopped unexpectedly.")
    ParentStopped -> {
      process.send_abnormal_exit(child, Shutdown)
      wait_loop(child, selector)
    }
    LinkedExit(exit) -> {
      // All links in this private worker were created by its startup callback,
      // never by its caller. The main child's exact monitor is authoritative.
      case exit.pid == child, exit.reason {
        True, _ | False, process.Normal -> Nil
        False, _ -> {
          io.println("A dotes application child stopped unexpectedly.")
          process.send_abnormal_exit(child, Shutdown)
        }
      }
      wait_loop(child, selector)
    }
  }
}

fn drain_owned_exits() -> Nil {
  let selector =
    process.new_selector()
    |> process.select_trapped_exits(fn(_) { Nil })
  case process.selector_receive(selector, 0) {
    Ok(Nil) -> drain_owned_exits()
    Error(Nil) -> Nil
  }
}
