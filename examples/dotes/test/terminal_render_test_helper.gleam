import dotes/tui
import gleam/erlang/atom
import gleam/erlang/process
import gleam/erlang/reference
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import shore
import shore/internal

type Geometry {
  Columns
  Rows
}

type GeometryRequest {
  GetGeometry(Geometry)
}

type IoRequest {
  IoRequest(process.Pid, reference.Reference, GeometryRequest)
}

type IoReply {
  IoReply(reference.Reference, Int)
}

type GeometryMessage {
  Request(IoRequest)
  Stop
}

pub type Problem {
  GeometryTimedOut
  LeaderChangeFailed
  LeaderRestoreFailed
  StartFailed(String)
  FrameTimedOut
  ExitTimedOut
  MissingRestoration
  TerminalStopTimedOut
  GeometryStopTimedOut
}

pub type RenderError {
  RenderError(primary: Option(Problem), cleanup: List(Problem))
}

pub opaque type Cleanup {
  Cleanup(
    geometry: #(process.Pid, process.Monitor),
    terminal: Option(#(process.Pid, process.Monitor)),
    ready: process.Subject(process.Subject(GeometryMessage)),
    frames: process.Subject(String),
    exit: process.Subject(Nil),
    initialising: process.Subject(process.Pid),
    leader: process.Pid,
    discarded_frames: List(String),
  )
}

/// Capture Shore's real ANSI frames at a fixed 100-column, 40-row geometry.
pub fn render(model: tui.Model) -> String {
  let #(rendered, _) = try_render(model, fn() { Nil })
  let assert Ok(output) = rendered
  output
}

/// Keep startup/frame failures as values until all invocation resources are
/// cleaned up. The callback runs in Shore's initial view, for bounded tests.
pub fn try_render(
  model: tui.Model,
  before_view: fn() -> Nil,
) -> #(Result(String, RenderError), Cleanup) {
  let previous = group_leader()
  let ready = process.new_subject()
  let geometry =
    process.spawn(fn() {
      let stop = process.new_subject()
      process.send(ready, stop)
      process.new_selector()
      |> process.select(stop)
      |> select_geometry(#(atom.create("io_request"), 4), Request)
      |> geometry_loop
    })
  let geometry_monitor = process.monitor(geometry)
  let stopped_by = process.receive(ready, 1000)
  let frames = process.new_subject()
  let exit = process.new_subject()
  let initialising = process.new_subject()
  let started = case stopped_by {
    Error(Nil) -> Error(GeometryTimedOut)
    Ok(_) ->
      case set_group_leader(geometry, process.self()) {
        False -> Error(LeaderChangeFailed)
        True ->
          shore.spec(
            init: fn() {
              process.send(initialising, process.self())
              #(model, [])
            },
            view: fn(model) {
              before_view()
              tui.view(model)
            },
            update: tui.update,
            exit:,
            keybinds: shore.default_keybinds(),
            redraw: shore.on_update(),
          )
          |> internal.start_custom_renderer(Some(frames))
          |> result.map_error(fn(error) { StartFailed(string.inspect(error)) })
      }
  }
  // Restore before handling even an unsuccessful Shore start.
  let restored_leader = set_group_leader(previous, process.self())
  let terminal = case process.receive(initialising, 0) {
    Ok(owner) -> Some(#(owner, process.monitor(owner)))
    Error(Nil) -> None
  }
  let output = {
    use _ <- result.try(started)
    list.try_map([1, 2, 3, 4], fn(_) {
      process.receive(frames, 1000) |> result.map_error(fn(_) { FrameTimedOut })
    })
    |> result.map(string.concat)
  }
  let exit_result = case started {
    Error(_) -> Ok(Nil)
    Ok(terminal) -> {
      process.send(terminal, shore.exit())
      process.receive(exit, 1000) |> result.map_error(fn(_) { ExitTimedOut })
    }
  }
  let terminal_stopped = case terminal {
    Some(#(owner, monitor)) ->
      await_stopped(owner, monitor)
      |> result.map_error(fn(_) { TerminalStopTimedOut })
    None -> Ok(Nil)
  }
  case stopped_by {
    Ok(stop) -> process.send(stop, Stop)
    Error(Nil) -> {
      process.unlink(geometry)
      process.kill(geometry)
    }
  }
  let geometry_stopped =
    await_stopped(geometry, geometry_monitor)
    |> result.map_error(fn(_) { GeometryStopTimedOut })
  // Producers are down before draining only this invocation's subjects.
  let discarded_frames = drain(frames)
  let _ = drain(ready)
  let _ = drain(exit)
  let _ = drain(initialising)
  let cleanup =
    list.flatten([
      case restored_leader {
        True -> []
        False -> [LeaderRestoreFailed]
      },
      case exit_result {
        Ok(Nil) -> []
        Error(problem) -> [problem]
      },
      case terminal_stopped {
        Ok(Nil) -> []
        Error(problem) -> [problem]
      },
      case geometry_stopped {
        Ok(Nil) -> []
        Error(problem) -> [problem]
      },
      case started {
        Error(_) -> []
        Ok(_) ->
          case list.contains(discarded_frames, internal.restore_terminal()) {
            True -> []
            False -> [MissingRestoration]
          }
      },
    ])
  let rendered = case output, cleanup {
    Ok(output), [] -> Ok(output)
    Ok(_), [_, ..] -> Error(RenderError(None, cleanup))
    Error(problem), _ -> Error(RenderError(Some(problem), cleanup))
  }
  #(
    rendered,
    Cleanup(
      geometry: #(geometry, geometry_monitor),
      terminal:,
      ready:,
      frames:,
      exit:,
      initialising:,
      leader: previous,
      discarded_frames:,
    ),
  )
}

/// Check the exact resources without consuming unrelated messages or monitors.
pub fn is_clean(cleanup: Cleanup) -> Bool {
  group_leader() == cleanup.leader
  && helper_stopped(cleanup.geometry)
  && case cleanup.terminal {
    None -> True
    Some(terminal) -> helper_stopped(terminal)
  }
  && process.receive(cleanup.ready, 0) == Error(Nil)
  && process.receive(cleanup.frames, 0) == Error(Nil)
  && process.receive(cleanup.exit, 0) == Error(Nil)
  && process.receive(cleanup.initialising, 0) == Error(Nil)
}

/// Frames discarded during cleanup, including a partially initialized terminal.
pub fn discarded_frames(cleanup: Cleanup) -> List(String) {
  cleanup.discarded_frames
}

fn helper_stopped(helper: #(process.Pid, process.Monitor)) -> Bool {
  !process.is_alive(helper.0)
  && process.new_selector()
  |> process.select_specific_monitor(helper.1, fn(down) { down })
  |> process.selector_receive(0)
  |> result.is_error
}

fn drain(subject: process.Subject(message)) -> List(message) {
  case process.receive(subject, 0) {
    Ok(message) -> [message, ..drain(subject)]
    Error(Nil) -> []
  }
}

fn geometry_loop(selector: process.Selector(GeometryMessage)) -> Nil {
  case process.selector_receive_forever(selector) {
    Stop -> Nil
    Request(IoRequest(from, reply, GetGeometry(geometry))) -> {
      let size = case geometry {
        Columns -> 100
        Rows -> 40
      }
      let _ = send_reply(from, IoReply(reply, size))
      geometry_loop(selector)
    }
  }
}

fn await_stopped(
  owner: process.Pid,
  monitor: process.Monitor,
) -> Result(Nil, Nil) {
  let selector =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
  let stopped = process.selector_receive(selector, 1000)
  case stopped {
    Ok(_) -> Nil
    Error(Nil) -> {
      process.unlink(owner)
      process.kill(owner)
      let _ = process.selector_receive_forever(selector)
      Nil
    }
  }
  process.demonitor_process(monitor)
  result.map(stopped, fn(_) { Nil })
}

@external(erlang, "erlang", "group_leader")
fn group_leader() -> process.Pid

@external(erlang, "erlang", "group_leader")
fn set_group_leader(leader: process.Pid, process: process.Pid) -> Bool

@external(erlang, "gleam_erlang_ffi", "insert_selector_handler")
fn select_geometry(
  selector: process.Selector(GeometryMessage),
  tag: #(atom.Atom, Int),
  mapping: fn(IoRequest) -> GeometryMessage,
) -> process.Selector(GeometryMessage)

@external(erlang, "erlang", "send")
fn send_reply(to: process.Pid, reply: IoReply) -> IoReply
