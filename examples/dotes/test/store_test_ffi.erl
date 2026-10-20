-module(store_test_ffi).
-export([contention/1, run_case/2, main/0, install/1,
         checkpoint/0, resume/1, last_writer/0, opening_owner/1,
         await_queued/1, close_attempts/0, assert_no_protocol_leaks/0,
         close/1, insert/2, delete_key/2, open_exclusive_set/3, ensure_loaded/0,
         capture_output/1]).

%% Test-only BEAM rewriting, following the root exclusive-session fixtures.
%% Each installation runs in its own disposable VM. No production debug hooks,
%% forged Store values, unlocked opens, or manual closes of exclusive handles.
install(Mode) ->
    true = register(dotes_store_test_controller, self()),
    ok = application:set_env(dotes_store_test, fault, Mode),
    lists:foreach(fun(Module) ->
        {module, Module} = code:ensure_loaded(Module),
        Beam = code:which(Module),
        {ok, {Module, [{abstract_code, {raw_abstract_v1, Forms}}]}} =
            beam_lib:chunks(Beam, [abstract_code]),
        {ok, Module, Binary} = compile:forms(rewrite(Forms, Module, Mode), [binary]),
        {module, Module} = code:load_binary(Module, Beam, Binary)
    end, ['slate@set', 'slate@bag', 'slate@duplicate_bag',
          'slate@internal@exclusive_session']),
    nil.

rewrite({remote, L, {atom, ML, slate_dets_ffi}, {atom, FL, Function}} = Original,
        Module, Mode) ->
    Replace = case Function of
        close -> true;
        insert -> Module =:= 'slate@duplicate_bag';
        delete_key ->
            (Module =:= 'slate@bag' andalso Mode =:= retry_tags) orelse
            (Module =:= 'slate@duplicate_bag' andalso Mode =:= retry_history);
        open_exclusive_set -> Mode =:= owner_dies_during_startup;
        _ -> false
    end,
    case Replace of
        true -> {remote, L, {atom, ML, ?MODULE}, {atom, FL, Function}};
        false -> Original
    end;
rewrite({remote, L, {atom, ML, slate_lock_nif}, {atom, FL, ensure_loaded}},
        _Module, native_unavailable) ->
    {remote, L, {atom, ML, ?MODULE}, {atom, FL, ensure_loaded}};
rewrite(Tuple, Module, Mode) when is_tuple(Tuple) ->
    list_to_tuple([rewrite(Element, Module, Mode) || Element <- tuple_to_list(Tuple)]);
rewrite(List, Module, Mode) when is_list(List) ->
    [rewrite(Element, Module, Mode) || Element <- List];
rewrite(Value, _Module, _Mode) -> Value.

mode() -> application:get_env(dotes_store_test, fault, none).

controller() -> whereis(dotes_store_test_controller).

table_file(Table) ->
    unicode:characters_to_binary(
        filename:basename(dets:info(slate_dets_ffi:table_name(Table), filename))).

denied() ->
    {error, {access_denied,
             {file_error_context, none, <<"private-injected-diagnostic">>}}}.

close(Table) ->
    File = table_file(Table),
    controller() ! {close_attempt, File},
    case {mode(), File} of
        {cleanup_failures, <<"history.dets">>} -> denied();
        {cleanup_failures, <<"tags.dets">>} -> denied();
        {nested_startup_failure, <<"counter.dets">>} -> denied();
        {parent_dies_during_cleanup, <<"history.dets">>} ->
            pause(),
            slate_dets_ffi:close(Table);
        {parent_dies_during_cleanup, <<"tags.dets">>} -> denied();
        {owner_dies_during_close, <<"history.dets">>} ->
            %% One shot, even when the next store has a different guardian.
            ok = application:set_env(dotes_store_test, fault, none),
            pause(),
            slate_dets_ffi:close(Table);
        _ -> slate_dets_ffi:close(Table)
    end.

insert(Table, Objects) ->
    controller() ! {owner_seen, self()},
    case mode() of
        Mode when Mode =:= serial_updates; Mode =:= update_then_delete;
                  Mode =:= owner_dies_during_request ->
            case put(dotes_archive_paused, true) of
                undefined -> pause();
                true -> ok
            end;
        _ -> ok
    end,
    slate_dets_ffi:insert(Table, Objects).

delete_key(Table, Key) ->
    case put(dotes_delete_failed, true) of
        undefined -> denied();
        true -> slate_dets_ffi:delete_key(Table, Key)
    end.

open_exclusive_set(Path, Repair, Access) ->
    case {mode(), filename:basename(Path)} of
        {owner_dies_during_startup, <<"notes.dets">>} ->
            ok = application:set_env(dotes_store_test, fault, none),
            pause();
        _ -> ok
    end,
    slate_dets_ffi:open_exclusive_set(Path, Repair, Access).

ensure_loaded() ->
    {error, {native_unavailable, <<"private-injected-diagnostic">>}}.

pause() ->
    controller() ! {checkpoint, self()},
    receive continue -> ok
    after 10000 -> error(fault_checkpoint_not_released)
    end.

checkpoint() ->
    receive {checkpoint, Pid} -> Pid
    after 5000 -> error(fault_checkpoint_not_reached)
    end.

resume(Pid) -> Pid ! continue, nil.

last_writer() ->
    receive {owner_seen, Pid} -> last_writer(Pid)
    after 5000 -> error(no_store_writer)
    end.

last_writer(Pid) ->
    receive {owner_seen, Next} -> last_writer(Next)
    after 0 -> Pid
    end.

opening_owner(Guardian) ->
    %% At the open checkpoint no table monitor exists yet. The native guardian
    %% monitors only its callback owner; do not inspect/forge opaque Store data.
    {monitors, [{process, Owner}]} = process_info(Guardian, monitors),
    Owner.

await_queued(Owner) ->
    await_queued(Owner, erlang:monotonic_time(millisecond) + 5000).

await_queued(Owner, Deadline) ->
    case process_info(Owner, message_queue_len) of
        {message_queue_len, Length} when Length > 0 -> nil;
        Other ->
            case erlang:monotonic_time(millisecond) >= Deadline of
                true -> error({store_request_not_queued, Other});
                false -> receive after 1 -> await_queued(Owner, Deadline) end
            end
    end.

close_attempts() ->
    receive {close_attempt, File} -> [File | close_attempts()]
    after 0 -> []
    end.

assert_no_protocol_leaks() ->
    {monitors, []} = process_info(self(), monitors),
    {messages, Messages} = process_info(self(), messages),
    [] = [Message || Message <- Messages, protocol_message(Message)],
    nil.

protocol_message({'DOWN', _, _, _, _}) -> true;
protocol_message({'EXIT', _, _}) -> true;
protocol_message({Reference, _}) when is_reference(Reference) -> true;
protocol_message(_) -> false.

%% Cross-VM tests use real native locks and actual dotes stores. The command
%% protocol is private/trusted test input, not a public external-term boundary.
contention(Directory) ->
    with_vms(Directory, fun(A, B, Path) ->
        {ok, nil} = command(A, {open, Path}),
        {ok, 1} = command(A, {create, <<"original">>}),
        Busy = {error, {sessions,
                       [{session_issue, counter, {acquisition_failed, busy}}]}},
        Busy = command(B, {open, Path}),
        {ok, nil} = command(A, close),
        %% No retry after close: acknowledgement must follow native release.
        {ok, nil} = command(B, {open, Path}),
        {ok, {note, _, <<"original">>, _}} = command(B, get),
        {ok, nil} = command(B, {update, <<"B">>}),
        Busy = command(A, {open, Path}),
        {ok, nil} = command(B, close),
        {ok, nil} = command(A, {open, Path}),
        {ok, {note, _, <<"B">>, _}} = command(A, get),
        {ok, [{revision, <<"original">>, _}]} = command(A, history),
        {ok, nil} = command(A, close)
    end).

run_case(Case, Directory) ->
    Path = unicode:characters_to_binary(filename:absname(Directory)),
    VM = start_vm(),
    try
        nil = command(VM, {run_case, Case, Path}),
        nil
    after
        stop_vm(VM),
        %% Never delete live sidecars, including quarantined ones.
        cleanup(Path)
    end.

with_vms(Directory, Check) ->
    Path = unicode:characters_to_binary(filename:absname(Directory)),
    A = start_vm(),
    try
        B = start_vm(),
        try Check(A, B, Path), nil
        after stop_vm(B) end
    after stop_vm(A), cleanup(Path) end.

start_vm() ->
    Erl = os:find_executable("erl", filename:join(code:root_dir(), "bin")),
    Paths = [filename:absname(P) || P <- code:get_path(), filelib:is_dir(P)],
    Port = open_port({spawn_executable, Erl},
        [binary, exit_status, use_stdio, stderr_to_stdout, {line, 65536},
         {args, ["+S", "2:2", "+A", "1", "-noshell", "-pa"] ++ Paths ++
                ["-eval", "store_test_ffi:main()."]}]),
    try ready = event(Port), Port
    catch Class:Reason:Stack ->
        force_stop_vm(Port),
        erlang:raise(Class, Reason, Stack)
    end.

command(Port, Term) ->
    send(Port, Term),
    {result, Result} = event(Port),
    Result.

send(Port, Term) ->
    true = port_command(Port, io_lib:format("~w.~n", [Term])),
    ok.

event(Port) -> event(Port, [], erlang:monotonic_time(millisecond) + 15000).

event(Port, Logs, Deadline) ->
    receive
        {Port, {data, {eol, <<"DOTES ", Text/binary>>}}} ->
            {ok, Tokens, _} = erl_scan:string(binary_to_list(Text) ++ "."),
            {ok, Term} = erl_parse:parse_term(Tokens),
            Term;
        {Port, {data, Line}} -> event(Port, [Line | Logs], Deadline);
        {Port, {exit_status, Status}} ->
            error({vm_exited, Status, lists:reverse(Logs)})
    after max(0, Deadline - erlang:monotonic_time(millisecond)) ->
        error({vm_event_timeout, lists:reverse(Logs)})
    end.

stop_vm(Port) ->
    case erlang:port_info(Port) of
        undefined -> ok;
        _ ->
            send(Port, stop),
            wait_exit(Port, erlang:monotonic_time(millisecond) + 10000)
    end.

wait_exit(Port, Deadline) ->
    receive
        {Port, {data, _}} -> wait_exit(Port, Deadline);
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, Status}} -> error({vm_stop_failed, Status})
    after max(0, Deadline - erlang:monotonic_time(millisecond)) ->
        force_stop_vm(Port),
        error(vm_stop_timeout)
    end.

force_stop_vm(Port) ->
    case erlang:port_info(Port, os_pid) of
        undefined -> ok;
        {os_pid, Pid} ->
            {Executable, Args} = case os:type() of
                {win32, _} -> {"taskkill", ["/PID", integer_to_list(Pid), "/T", "/F"]};
                {unix, _} -> {"kill", ["-KILL", integer_to_list(Pid)]}
            end,
            Killer = open_port({spawn_executable, os:find_executable(Executable)},
                [binary, exit_status, use_stdio, stderr_to_stdout, {args, Args}]),
            wait_exit(Killer, erlang:monotonic_time(millisecond) + 10000),
            drain_exit(Port, erlang:monotonic_time(millisecond) + 10000)
    end.

drain_exit(Port, Deadline) ->
    receive
        {Port, {data, _}} -> drain_exit(Port, Deadline);
        {Port, {exit_status, _}} -> ok
    after max(0, Deadline - erlang:monotonic_time(millisecond)) ->
        error(killed_vm_did_not_exit)
    end.

cleanup(Path) ->
    case file:del_dir_r(Path) of
        ok -> ok;
        {error, enoent} -> ok;
        Error -> error({fixture_cleanup_failed, Path, Error})
    end.

main() ->
    emit(ready),
    loop(undefined).

loop(Store) ->
    case read_command() of
        {run_case, Case, Path} ->
            nil = store_fault_cases:run(Case, Path),
            emit({result, nil}),
            loop(Store);
        {open, Path} ->
            case 'dotes@store':open_in(Path) of
                {ok, Next} -> emit({result, {ok, nil}}), loop(Next);
                {error, _} = Error -> emit({result, Error}), loop(Store)
            end;
        {create, Body} ->
            emit({result, 'dotes@store':create_note(Store, <<"title">>, Body)}),
            loop(Store);
        {update, Body} ->
            emit({result, 'dotes@store':update_note(Store, 1, Body)}),
            loop(Store);
        get -> emit({result, 'dotes@store':get_note(Store, 1)}), loop(Store);
        history -> emit({result, 'dotes@store':get_history(Store, 1)}), loop(Store);
        close -> emit({result, 'dotes@store':close(Store)}), loop(undefined);
        stop -> erlang:halt(0)
    end.

read_command() ->
    case io:get_line("") of
        eof -> erlang:halt(0);
        Line ->
            {ok, Tokens, _} = erl_scan:string(Line),
            {ok, Term} = erl_parse:parse_term(Tokens),
            Term
    end.

emit(Term) -> io:format("DOTES ~w~n", [Term]).

%% A real IO protocol recorder, not an instrumentation replacement for logging.
%% Descendants inherit it; the recorder outlives the closing parent under test.
capture_output(Run) ->
    Original = group_leader(),
    Recorder = spawn(fun() -> record_output(Original, []) end),
    true = group_leader(Recorder, self()),
    try
        nil = Run(),
        Reference = make_ref(),
        Recorder ! {finish, self(), Reference},
        receive {Reference, Output} -> Output
        after 5000 -> error(output_recorder_timeout) end
    after
        true = group_leader(Original, self()),
        exit(Recorder, kill)
    end.

record_output(Original, Acc) ->
    receive
        {io_request, From, ReplyAs, Request} ->
            Reply = io:request(Original, Request),
            From ! {io_reply, ReplyAs, Reply},
            record_output(Original, [output_text(Request) | Acc]);
        {finish, Caller, Reference} ->
            Caller ! {Reference, unicode:characters_to_binary(lists:reverse(Acc))}
    end.

output_text({put_chars, _Encoding, Chars}) -> Chars;
output_text({put_chars, _Encoding, Module, Function, Args}) ->
    apply(Module, Function, Args);
output_text({put_chars, Chars}) -> Chars;
output_text({put_chars, Module, Function, Args}) -> apply(Module, Function, Args);
output_text({requests, Requests}) -> [output_text(R) || R <- Requests];
output_text(_) -> [].
