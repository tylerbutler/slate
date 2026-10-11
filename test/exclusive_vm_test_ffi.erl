-module(exclusive_vm_test_ffi).
-include_lib("kernel/include/file.hrl").
-export([contention/1, repeated_sessions/1, owner_exit/0, guardian_exit/0,
         callback_failures/0, extra_user/0, vm_crash/0, aliases/0, hard_links/0,
         different_files/0, open_exit/1, close_exit/1, cleanup_failures/0,
         waiting_owner_exit/0, tmpfs_contention/0, unicode_paths/0,
         case_and_short_aliases/0, repair_sidecar/0, release_failures/0,
         undelivered_cleanup/0, guardian_exit_primary/0, poisoned_path/0]).

poisoned_path() ->
    Directory = filename:absname(filename:join("build", "exclusive-vm-poison-" ++
                                integer_to_list(erlang:unique_integer([positive])))),
    Name = case os:type() of {win32, _} -> "erl.exe"; {unix, _} -> "erl" end,
    BrokenErl = filename:join(Directory, Name),
    Separator = case os:type() of {win32, _} -> ";"; {unix, _} -> ":" end,
    SavedPath = os:getenv("PATH"),
    ok = filelib:ensure_dir(BrokenErl),
    try
        ok = file:write_file(BrokenErl, <<"not an Erlang launcher\n">>),
        ok = file:change_mode(BrokenErl, 8#755),
        %% Locked startest 0.8 runs tests synchronously; always restore PATH.
        true = os:putenv("PATH", Directory ++ Separator ++ os:getenv("PATH", "")),
        BrokenErl = os:find_executable("erl"),
        Port = start_vm(),
        try nil
        after stop_vm(Port) end
    after
        case SavedPath of
            false -> true = os:unsetenv("PATH");
            _ -> true = os:putenv("PATH", SavedPath)
        end,
        delete(BrokenErl),
        ok = file:del_dir(Directory)
    end.

contention(Type) -> contention_at(Type, path("contention", Type)).

contention_at(Type, FilePath) ->
    with_vms(FilePath, fun(A, B, Path) ->
        send_session(A, Path, Type, immediate, hold),
        opening = event(A), holding = event(A),
        send_session(B, Path, Type, immediate, hold),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        send_session(B, Path, Type, {wait_up_to, 100}, hold),
        Started = erlang:monotonic_time(millisecond),
        {result, {error, {acquisition_failed, timed_out}}} = event(B),
        true = erlang:monotonic_time(millisecond) - Started >= 80,
        true = erlang:monotonic_time(millisecond) - Started < 1000,
        send_session(B, Path, Type, immediate, hold),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        send_session(B, Path, Type, {wait_up_to, 3000}, {insert, <<"b">>, 2}),
        no_event(B, 50),
        send(A, {finish, {insert, <<"a">>, 1}}),
        {result, {ok, nil}} = event(A),
        opening = event(B), {result, {ok, nil}} = event(B),
        {ok, 1} = run_session(B, Path, Type, {lookup, <<"a">>}),
        {ok, 2} = run_session(A, Path, Type, {lookup, <<"b">>})
    end).

tmpfs_contention() ->
    case os:type() of
        {unix, linux} ->
            lists:foreach(fun(Type) ->
                contention_at(Type, list_to_binary("/dev/shm/slate_test_exclusive_" ++
                              os:getpid() ++ "_" ++ atom_to_list(Type) ++ ".dets"))
            end, [set, bag, duplicate_bag]);
        _ -> ok
    end,
    nil.

waiting_owner_exit() ->
    with_vms(path("waiting_exit", set), fun(A, B, Path) ->
        send_session(A, Path, set, immediate, hold),
        opening = event(A), holding = event(A),
        send_session(B, Path, set, {wait_up_to, 3000}, return_ok),
        no_event(B, 50),
        send(B, kill_owner), owner_killed = event(B),
        send(A, {finish, return_ok}), {result, {ok, nil}} = event(A),
        {ok, nil} = run_session(B, Path, set, return_ok)
    end).

open_exit(Who) ->
    with_vms(path("open_exit_" ++ atom_to_list(Who), set), fun(A, B, Path) ->
        send_session(A, Path, set, immediate, block_open),
        opening = event(A), open_blocked = event(A),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        case Who of
            owner ->
                send(A, kill_owner), owner_killed = event(A),
                send(A, continue_open),
                {ok, nil} = run_session(B, Path, set, return_ok);
            guardian ->
                send(A, kill_guardian), guardian_killed = event(A),
                {result, {error, {cleanup_failed, none, [{guardian_stopped, _}]}}} = event(A),
                send(A, get_log),
                {log, #{event := slate_exclusive_guardian_stopped, reason := killed}} = event(A),
                send_session(B, Path, set, immediate, return_ok),
                {result, {error, {acquisition_failed, busy}}} = event(B),
                send(A, halt_vm), wait_exit(A, 70),
                {ok, nil} = run_session(B, Path, set, return_ok)
        end
    end).

close_exit(Who) ->
    with_vms(path("close_exit_" ++ atom_to_list(Who), set), fun(A, B, Path) ->
        send_session(A, Path, set, immediate, block_close),
        opening = event(A), close_ready = event(A),
        send(A, pause_table), close_blocked = event(A),
        send(A, await_close), close_waiting = event(A),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        case Who of
            owner ->
                send(A, kill_owner), owner_killed = event(A),
                send(A, resume_table), table_resumed = event(A),
                {ok, nil} = run_session(B, Path, set, return_ok);
            guardian ->
                send(A, kill_guardian), guardian_killed = event(A),
                {result, {error, {cleanup_failed, none, [{guardian_stopped, _}]}}} = event(A),
                send(A, resume_table), table_resumed = event(A),
                send_session(B, Path, set, immediate, return_ok),
                {result, {error, {acquisition_failed, busy}}} = event(B),
                send(A, halt_vm), wait_exit(A, 70),
                {ok, nil} = run_session(B, Path, set, return_ok)
        end
    end).

cleanup_failures() ->
    with_vms(path("close_failure", set), fun(A, B, Path) ->
        {error, {cleanup_failed, {some, {callback_failure, not_found}},
                 [{close_failure, CloseError}]}} =
            run_session(A, Path, set, kill_table_then_error),
        true = lists:member(CloseError, [table_does_not_exist,
                                        {unexpected_error, <<"not_owner">>}]),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B)
    end),
    with_vms(path("exception_cleanup", set), fun(A, B, Path) ->
        {exception, error, exclusive_fixture_exception} =
            run_session(A, Path, set, add_user_then_raise),
        send(A, get_log),
        {log, #{event := slate_exclusive_cleanup_failed,
                exception_class := error, exception_reason := exclusive_fixture_exception,
                error := {cleanup_failed, none, [{close_failure, _}]}}} = event(A),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B)
    end),
    with_vms(path("owner_cleanup", set), fun(A, B, Path) ->
        send_session(A, Path, set, immediate, add_user_then_hold),
        opening = event(A), holding = event(A),
        send(A, kill_owner), owner_killed = event(A),
        send(A, get_log),
        {log, #{event := slate_exclusive_cleanup_failed, owner_exit := killed,
                failures := [{close_failure, _}]}} = event(A),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B)
    end).

release_failures() ->
    with_vms(path("late_acquisition", set), fun(A, B, Path) ->
        send(A, {inject_release_failure, late_acquire_success}), fault_injected = event(A),
        %% Allow cold Gleam module startup; the stub expires the deadline only
        %% after acquiring a real token, so this actually tests late release.
        send_session(A, Path, set, {wait_up_to, 1000}, return_ok),
        {result, {error, {acquisition_failed, timed_out}}} = event(A),
        {error, enoent} = file:read_file_info(binary_to_list(Path)),
        {ok, nil} = run_session(B, Path, set, return_ok)
    end),
    with_vms(path("release_failure", set), fun(A, B, Path) ->
        send(A, {inject_release_failure, release_only}), fault_injected = event(A),
        {error, {cleanup_failed, {some, {callback_failure, not_found}},
                 [{release_failure, {os_failure, _}}]}} =
            run_session(A, Path, set, {insert_then_error, <<"kept">>, 7}),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        send(A, halt_vm), wait_exit(A, 70),
        {ok, 7} = run_session(B, Path, set, {lookup, <<"kept">>})
    end),
    with_vms(path("late_release_failure", set), fun(A, B, Path) ->
        send(A, {inject_release_failure, late_acquire}), fault_injected = event(A),
        send_session(A, Path, set, {wait_up_to, 1000}, return_ok),
        {result, {error, {cleanup_failed, {some, {acquisition_failure, timed_out}},
                         [{release_failure, {os_failure, _}}]}}} = event(A),
        {error, enoent} = file:read_file_info(binary_to_list(Path)),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        send(A, halt_vm), wait_exit(A, 70),
        {ok, nil} = run_session(B, Path, set, return_ok)
    end).

undelivered_cleanup() ->
    with_vms(path("undelivered_cleanup", set), fun(A, B, Path) ->
        send(A, {inject_release_failure, pause_delivery}), fault_injected = event(A),
        send_session(A, Path, set, immediate, {insert_then_error, <<"kept">>, 7}),
        opening = event(A),
        send(A, await_delivery), delivery_paused = event(A),
        send(A, kill_owner), owner_killed = event(A),
        send(A, get_log),
        {log, #{event := slate_exclusive_cleanup_failed, owner_exit := killed,
                error := {cleanup_failed, {some, {callback_failure, not_found}},
                          [{release_failure, {os_failure, _}}]}}} = event(A),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        send(A, halt_vm), wait_exit(A, 70),
        {ok, 7} = run_session(B, Path, set, {lookup, <<"kept">>})
    end).

repeated_sessions(Type) ->
    with_vms(path("repeated", Type), fun(A, B, Path) ->
        lists:foreach(fun(N) ->
            send_session(A, Path, Type, {wait_up_to, 3000}, {insert, {a, N}, N}),
            send_session(B, Path, Type, {wait_up_to, 3000}, {insert, {b, N}, N}),
            opening = event(A), {result, {ok, nil}} = event(A),
            opening = event(B), {result, {ok, nil}} = event(B),
            {ok, N} = run_session(A, Path, Type, {lookup, {b, N}}),
            {ok, N} = run_session(B, Path, Type, {lookup, {a, N}})
        end, lists:seq(1, 5)),
        case Type of
            set ->
                lists:foreach(fun(_) ->
                    send_session(A, Path, set, {wait_up_to, 3000}, {increment, <<"counter">>}),
                    send_session(B, Path, set, {wait_up_to, 3000}, {increment, <<"counter">>}),
                    opening = event(A), {result, {ok, nil}} = event(A),
                    opening = event(B), {result, {ok, nil}} = event(B)
                end, lists:seq(1, 10)),
                {ok, 20} = run_session(A, Path, set, {lookup, <<"counter">>}),
                {ok, nil} = run_session(A, Path, set, {insert, <<"same">>, 1}),
                {ok, nil} = run_session(B, Path, set, {insert, <<"same">>, 2}),
                {ok, 2} = run_session(A, Path, set, {lookup, <<"same">>});
            bag -> ok;
            duplicate_bag -> ok
        end
    end).

owner_exit() ->
    with_vms(path("owner_exit", set), fun(A, B, Path) ->
        send_session(A, Path, set, immediate, hold),
        opening = event(A), holding = event(A),
        send(A, kill_owner), owner_killed = event(A),
        {ok, nil} = run_session(B, Path, set, {insert, <<"after">>, 1})
    end).

guardian_exit() ->
    with_vms(path("guardian_exit", set), fun(A, B, Path) ->
        send_session(A, Path, set, immediate, hold),
        opening = event(A), holding = event(A),
        send(A, kill_guardian), guardian_killed = event(A),
        send(A, {finish, return_ok}),
        {result, {error, {cleanup_failed, none, [{guardian_stopped, _}]}}} = event(A),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        send(A, halt_vm), wait_exit(A, 70),
        {ok, nil} = run_session(B, Path, set, return_ok)
    end).

guardian_exit_primary() ->
    with_vms(path("guardian_exit_primary", set), fun(A, B, Path) ->
        send_session(A, Path, set, immediate, hold),
        opening = event(A), holding = event(A),
        send(A, kill_guardian), guardian_killed = event(A),
        send(A, {finish, return_error}),
        {result, {error, {cleanup_failed, {some, {callback_failure, not_found}},
                         [{guardian_stopped, _}]}}} = event(A),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        send(A, halt_vm), wait_exit(A, 70),
        {ok, nil} = run_session(B, Path, set, return_ok)
    end).

callback_failures() ->
    with_vms(path("callback_failures", set), fun(A, B, Path) ->
        {error, {session_failed, {callback_failure, not_found}}} =
            run_session(A, Path, set, {insert_then_error, <<"kept">>, 7}),
        {ok, 7} = run_session(B, Path, set, {lookup, <<"kept">>}),
        lists:foreach(fun(Class) ->
            {exception, Class, exclusive_fixture_exception} =
                run_session(A, Path, set, {raise, Class}),
            {ok, 7} = run_session(B, Path, set, {lookup, <<"kept">>})
        end, [error, throw, exit])
    end).

extra_user() ->
    with_vms(path("extra_user", set), fun(A, B, Path) ->
        {error, {cleanup_failed, {some, {callback_failure, not_found}},
                 [{close_failure, {unexpected_error, <<"exclusive_table_still_open">>}}]}} =
            run_session(A, Path, set, add_user_then_error),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        send(A, stop_extra), extra_stopped = event(A),
        send_session(B, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, busy}}} = event(B),
        send(A, halt_vm), wait_exit(A, 70),
        {ok, nil} = run_session(B, Path, set, return_ok)
    end).

vm_crash() ->
    with_vms(path("crash", set), fun(A, B, Path) ->
        {ok, nil} = run_session(A, Path, set, {insert, <<"before">>, 2}),
        {ok, File} = file:open(binary_to_list(Path), [read, binary]),
        {ok, <<Clean>>} = file:pread(File, 11, 1),
        ok = file:close(File),
        send_session(A, Path, set, immediate, hold),
        opening = event(A), holding = event(A),
        send(A, halt_vm), wait_exit(A, 70),
        % Force the known dirty marker so repair assertions do not depend on crash timing.
        {ok, Dirty} = file:open(binary_to_list(Path), [read, write, binary]),
        ok = file:pwrite(Dirty, 11, <<(Clean bxor 1)>>),
        ok = file:close(Dirty),
        send(B, {session_with, Path, set, no_repair, read_write, immediate, return_ok}),
        opening = event(B),
        {result, {error, {session_failed, {open_failure, {needs_repair, _}}}}} = event(B),
        {ok, nil} = run_session(B, Path, set, return_ok),
        {ok, 2} = run_session(B, Path, set, {lookup, <<"before">>}),
        {ok, nil} = run_session(B, Path, set, {insert, <<"repaired">>, 3}),
        {ok, 3} = run_session(B, Path, set, {lookup, <<"repaired">>})
    end).

different_files() ->
    with_vms(path("different_a", set), fun(A, B, Path) ->
        Other = path("different_b", set),
        cleanup(Other),
        try
            send_session(A, Path, set, immediate, hold),
            opening = event(A), holding = event(A),
            {ok, nil} = run_session(B, Other, set, {insert, <<"independent">>, 1}),
            send(A, {finish, return_ok}),
            {result, {ok, nil}} = event(A)
        after cleanup(Other) end
    end).

unicode_paths() ->
    Path = unicode:characters_to_binary(filename:absname(
        "test_exclusive_unicode_caf" ++ [16#e9] ++ ".dets")),
    with_vms(Path, fun(A, B, _) ->
        {ok, nil} = run_session(A, Path, set, {insert, <<"unicode">>, 42}),
        {ok, _} = file:read_file_info(unicode:characters_to_list(Path)),
        {ok, 42} = run_session(B, Path, set, {lookup, <<"unicode">>})
    end).

case_and_short_aliases() ->
    Path = path("MixedCaseLongFilename", set),
    with_vms(Path, fun(A, B, _) ->
        {ok, nil} = run_session(A, Path, set, return_ok),
        Alias = string:uppercase(binary_to_list(Path)),
        case file:read_file_info(Alias) of
            {ok, _} ->
                send_session(A, Path, set, immediate, hold),
                opening = event(A), holding = event(A),
                send_session(B, list_to_binary(Alias), set, immediate, return_ok),
                {result, {error, {acquisition_failed, busy}}} = event(B),
                send(A, {finish, return_ok}), {result, {ok, nil}} = event(A);
            {error, enoent} ->
                true = os:type() =/= {win32, nt};
            {error, Reason} -> error({case_alias_failed, Reason})
        end,
        case os:type() of
            {win32, _} ->
                %% Keep nested CMD quotes out of Erlang's argument escaping.
                Command = "for %I in (%SLATE_TEST_LONG_PATH%) do @echo %~sI",
                Port = open_port({spawn_executable, os:find_executable("cmd")},
                    [binary, exit_status, use_stdio, stderr_to_stdout,
                     {args, ["/d", "/s", "/c", Command]},
                     {env, [{"SLATE_TEST_LONG_PATH", "\"" ++ binary_to_list(Path) ++ "\""}]}]),
                Short = string:trim(short_output(Port, [], erlang:monotonic_time(millisecond) + 5000)),
                true = string:lowercase(Short) =/= string:lowercase(binary_to_list(Path)),
                {ok, _} = file:read_file_info(Short),
                send_session(A, Path, set, immediate, hold),
                opening = event(A), holding = event(A),
                send_session(B, list_to_binary(Short), set, immediate, return_ok),
                {result, {error, {acquisition_failed, busy}}} = event(B),
                send(A, {finish, return_ok}), {result, {ok, nil}} = event(A);
            {unix, _} -> ok
        end
    end).

short_output(Port, Parts, Deadline) ->
    receive
        {Port, {data, Data}} -> short_output(Port, [Data | Parts], Deadline);
        {Port, {exit_status, 0}} -> binary_to_list(iolist_to_binary(lists:reverse(Parts)));
        {Port, {exit_status, Status}} -> error({short_path_command_failed, Status})
    after max(0, Deadline - erlang:monotonic_time(millisecond)) ->
        force_stop_vm(Port),
        error(short_path_timeout)
    end.

repair_sidecar() ->
    {ok, nil} = slate_lock_nif:ensure_loaded(),
    with_vms(path("repair_sidecar", set), fun(A, B, Path) ->
        {ok, nil} = run_session(A, Path, set, {insert, <<"before">>, 7}),
        Sidecar = binary_to_list(Path) ++ ".slate.lock",
        {ok, File} = file:open(Sidecar, [read, raw, binary]),
        try
            {ok, Before} = file:read_file_info(File),
            send(A, {session_with, Path, set, force_repair, read_write, immediate,
                     {lookup, <<"before">>}}),
            opening = event(A), {result, {ok, 7}} = event(A),
            {ok, After} = file:read_file_info(Sidecar),
            true = {Before#file_info.major_device, Before#file_info.inode} =:=
                   {After#file_info.major_device, After#file_info.inode},
            {ok, {Next, _}} = slate_lock_nif:acquire(Path),
            {ok, nil} = slate_lock_nif:release(Next),
            {ok, 7} = run_session(B, Path, set, {lookup, <<"before">>})
        after ok = file:close(File) end
    end).

aliases() ->
    Path = path("aliases", set),
    Alias = <<Path/binary, ".alias">>,
    cleanup(Path), delete(Alias),
    {ok, Table} = slate_dets_ffi:open_set(Path, no_repair),
    {ok, nil} = slate_dets_ffi:close(Table),
    case file:make_symlink(binary_to_list(Path), binary_to_list(Alias)) of
        ok ->
            try with_vms_existing(Path, fun(A, B, _) ->
                send_session(A, Path, set, immediate, hold),
                opening = event(A), holding = event(A),
                send_session(B, Alias, set, immediate, return_ok),
                {result, {error, {acquisition_failed, busy}}} = event(B),
                Relative = list_to_binary(filename:join(".", filename:basename(binary_to_list(Path)))),
                send_session(B, Relative, set, immediate, return_ok),
                {result, {error, {acquisition_failed, busy}}} = event(B),
                send(A, {finish, return_ok}), {result, {ok, nil}} = event(A),
                {ok, nil} = run_session(B, Alias, set, return_ok)
            end)
            after delete(Alias) end;
        {error, Reason} -> error({symlink_creation_failed, Reason})
    end.

hard_links() ->
    Path = path("hard_links", set),
    Alias = <<Path/binary, ".alias">>,
    cleanup(Path), delete(Alias),
    {ok, Table} = slate_dets_ffi:open_set(Path, no_repair),
    {ok, nil} = slate_dets_ffi:close(Table),
    ok = file:make_link(binary_to_list(Path), binary_to_list(Alias)),
    try with_vms_existing(Path, fun(A, B, _) ->
        send_session(A, Path, set, immediate, return_ok),
        {result, {error, {acquisition_failed, {unsafe_alias, _}}}} = event(A),
        send_session(B, Alias, set, immediate, return_ok),
        {result, {error, {acquisition_failed, {unsafe_alias, _}}}} = event(B)
    end)
    after delete(Alias) end.

with_vms(Path, Check) ->
    cleanup(Path),
    with_vms_existing(Path, Check).

with_vms_existing(Path, Check) ->
    A = start_vm(),
    try
        B = start_vm(),
        try Check(A, B, Path), nil
        after stop_vm(B) end
    after stop_vm(A), cleanup(Path) end.

start_vm() ->
    %% Windows erl prepends erts/bin to PATH, whose erl.ini may be stale.
    Erl = os:find_executable("erl", filename:join(code:root_dir(), "bin")),
    Ebin = filename:dirname(code:which(slate_exclusive_vm_fixture)),
    Port = open_port({spawn_executable, Erl},
        [binary, exit_status, use_stdio, stderr_to_stdout, {line, 65536},
         {args, ["+S", "2:2", "+A", "1", "-noshell", "-pa", Ebin,
                 filename:dirname(code:which('gleam@erlang@process')),
                 filename:dirname(code:which('gleam@result')),
                 "-eval", "slate_exclusive_vm_fixture:main()."]}]),
    try ready = event(Port), Port
    catch Class:Reason:Stack ->
        force_stop_vm(Port),
        erlang:raise(Class, Reason, Stack)
    end.

send(Port, Term) -> true = port_command(Port, io_lib:format("~w.~n", [Term])), ok.

send_session(Port, Path, Type, Wait, Action) ->
    send(Port, {session, Path, Type, Wait, Action}).

run_session(Port, Path, Type, Action) ->
    send_session(Port, Path, Type, {wait_up_to, 3000}, Action),
    opening = event(Port),
    {result, Result} = event(Port),
    Result.

event(Port) -> event(Port, [], erlang:monotonic_time(millisecond) + 10000).
event(Port, Logs, Deadline) ->
    receive
        {Port, {data, {eol, <<"SLATE ", Text/binary>>}}} ->
            {ok, Tokens, _} = erl_scan:string(binary_to_list(Text) ++ "."),
            {ok, Term} = erl_parse:parse_term(Tokens),
            Term;
        {Port, {data, Line}} -> event(Port, [Line | Logs], Deadline);
        {Port, {exit_status, Status}} -> error({vm_exited, Status, lists:reverse(Logs)})
    after max(0, Deadline - erlang:monotonic_time(millisecond)) ->
        error({vm_event_timeout, lists:reverse(Logs)})
    end.

no_event(Port, Delay) ->
    receive
        {Port, Message} -> error({unexpected_vm_event, Message})
    after Delay -> ok
    end.

wait_exit(Port, Status) ->
    wait_exit(Port, Status, erlang:monotonic_time(millisecond) + 10000).

wait_exit(Port, Status, Deadline) ->
    receive
        {Port, {data, _}} -> wait_exit(Port, Status, Deadline);
        {Port, {exit_status, Status}} -> ok;
        {Port, {exit_status, Other}} -> error({wrong_vm_exit, Other})
    after max(0, Deadline - erlang:monotonic_time(millisecond)) ->
        force_stop_vm(Port),
        error(vm_exit_timeout)
    end.

force_stop_vm(Port) ->
    case erlang:port_info(Port, os_pid) of
        undefined -> ok;
        {os_pid, Pid} ->
            {Command, Args} = case os:type() of
                {win32, _} -> {"taskkill", ["/PID", integer_to_list(Pid), "/T", "/F"]};
                {unix, _} -> {"kill", ["-KILL", integer_to_list(Pid)]}
            end,
            Killer = open_port({spawn_executable, os:find_executable(Command)},
                              [binary, exit_status, use_stdio, stderr_to_stdout, {args, Args}]),
            wait_killer(Killer, erlang:monotonic_time(millisecond) + 10000)
    end.

wait_killer(Port, Deadline) ->
    receive
        {Port, {data, _}} -> wait_killer(Port, Deadline);
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, Status}} -> error({vm_kill_failed, Status})
    after max(0, Deadline - erlang:monotonic_time(millisecond)) -> error(vm_kill_timeout)
    end.

stop_vm(Port) ->
    case erlang:port_info(Port) of
        undefined -> ok;
        _ ->
            send(Port, stop),
            wait_exit(Port, 0)
    end.

path(Test, Type) ->
    list_to_binary(filename:absname("test_exclusive_vm_" ++ Test ++ "_" ++ atom_to_list(Type) ++ ".dets")).

cleanup(Path) ->
    delete(Path),
    delete(<<Path/binary, ".slate.lock">>).

delete(Path) ->
    Filename = unicode:characters_to_list(Path),
    case file:delete(Filename) of
        ok -> ok;
        {error, enoent} -> ok;
        {error, Reason} -> error({fixture_cleanup_failed, Path, Reason})
    end.
