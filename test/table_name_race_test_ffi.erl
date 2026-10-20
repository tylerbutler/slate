-module(table_name_race_test_ffi).
-export([with_open_breakpoint/1, paused_openers/1, continue_open/1,
         disable_open_breakpoint/1, collision_check_breakpoint/1,
         await_coordination/1, table_pid/1, with_counter_breakpoint/1,
         with_insert_breakpoint/1, await_exclusive_coordination/1,
         with_opened_breakpoint/1, with_native_open_breakpoint/1,
         with_lifetime_fence_breakpoint/1, with_fence_result_breakpoint/1]).

await_exclusive_coordination(Owner) ->
    await_exclusive_coordination(Owner, erlang:monotonic_time(millisecond) + 5000).

await_exclusive_coordination(Owner, Deadline) ->
    case process_info(Owner, monitors) of
        {monitors, [{process, Guardian}]} when is_pid(Guardian) ->
            await_coordination(Guardian);
        State ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> timer:sleep(1), await_exclusive_coordination(Owner, Deadline);
                false -> error({guardian_not_started, State})
            end
    end.

%% Observe an actual failed acquisition/backoff, not a sleep that assumes
%% the competing opener was scheduled. global itself is not interpreted.
await_coordination(Pid) ->
    await_coordination(Pid, erlang:monotonic_time(millisecond) + 5000).

await_coordination(Pid, Deadline) ->
    {current_stacktrace, Stack} = process_info(Pid, current_stacktrace),
    case lists:any(fun
        ({global, random_sleep, _, _}) -> true;
        (_) -> false
    end, Stack) of
        true -> nil;
        false ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> timer:sleep(1), await_coordination(Pid, Deadline);
                false -> error({coordination_not_reached, Pid, Stack})
            end
    end.

table_pid({_Type, Reference, _KeyDecoder, _ValueDecoder}) ->
    slate_exclusive_table_ffi:table_pid(Reference).

%% gleam_erlang supplies all worker/message/monitor operations, but no debugger
%% API. Use a real OTP breakpoint, not sleeps or asynchronous trace/suspend,
%% to hold callers AFTER selection and BEFORE the lifetime reservation.
%% No production instrumentation or fake DETS responses are involved.
with_open_breakpoint(Callback) ->
    with_breakpoint(<<"case slate_dets_lifetime:begin_open(CanonicalPath, Candidate) of">>, Callback).

with_counter_breakpoint(Callback) ->
    with_breakpoint(<<"try dets:update_counter(table_name(Name), Key, Increment) of">>, Callback).

with_insert_breakpoint(Callback) ->
    with_breakpoint(<<"try dets:insert(table_name(Name), Objects) of">>, Callback).

with_opened_breakpoint(Callback) ->
    with_breakpoint(<<"ok = slate_dets_lifetime:opened(Token, dets:info(Name, owner))">>, Callback).

with_native_open_breakpoint(Callback) ->
    with_breakpoint(<<"OpenResult = try dets:open_file(Name, Options)">>, Callback).

with_lifetime_fence_breakpoint(Callback) ->
    with_breakpoint(slate_dets_lifetime,
                    <<"case dets:info(Name, owner) of">>, Callback).

with_fence_result_breakpoint(Callback) ->
    with_breakpoint(slate_dets_lifetime,
                    <<"Parent ! {fenced, self(), Token, TablePid}">>, Callback).

with_breakpoint(Marker, Callback) ->
    with_breakpoint(slate_dets_ffi, Marker, Callback).

with_breakpoint(Module, Marker, Callback) ->
    Source = filename:join(["src", atom_to_list(Module) ++ ".erl"]),
    {ok, Contents} = file:read_file(Source),
    Line = find_line(binary:split(Contents, <<"\n">>, [global]), Marker, 1),
    {module, Module} = int:i(Source),
    try
        ok = int:break(Module, Line),
        Callback({open_breakpoint, Module, Line})
    after
        %% Release paused callers even if a Gleam assertion raises. Worker
        %% lifetimes are otherwise bounded by typed receives and links.
        int:no_break(Module),
        [int:continue(Pid) || {Pid, _, break, _} <- int:snapshot()],
        ok = stop_interpreting(Module),
        int:clear()
    end.

stop_interpreting(slate_dets_lifetime = Module) ->
    %% int:n sends old_code to interpreter meta processes and can kill a
    %% process still executing that module. Unlike test workers, the registry
    %% remains alive: use the OTP system barrier to finish its current callback
    %% and keep it idle until interpretation has been disabled.
    case whereis(Module) of
        undefined -> int:n(Module);
        Pid ->
            ok = sys:suspend(Pid),
            try int:n(Module)
            after ok = sys:resume(Pid)
            end
    end;
stop_interpreting(Module) ->
    int:n(Module).

find_line([Line | Rest], Marker, Number) ->
    case binary:match(Line, Marker) of
        nomatch -> find_line(Rest, Marker, Number + 1);
        _ -> Number
    end;
find_line([], Marker, _) ->
    erlang:error({breakpoint_not_found, Marker}).

paused_openers({open_breakpoint, Module, Line}) ->
    [Pid || {Pid, _, break, {AtModule, AtLine}} <- int:snapshot(),
            AtModule =:= Module, AtLine =:= Line].

continue_open(Pid) ->
    case int:continue(Pid) of
        ok -> {ok, nil};
        {error, _} -> {error, nil}
    end.

disable_open_breakpoint({open_breakpoint, Module, Line}) ->
    ok = int:delete_break(Module, Line),
    nil.

collision_check_breakpoint({open_breakpoint, slate_dets_ffi, OpenLine}) ->
    {ok, Contents} = file:read_file(filename:join(["src", "slate_dets_ffi.erl"])),
    Lines = lists:nthtail(OpenLine, binary:split(Contents, <<"\n">>, [global])),
    Line = info_line(Lines, OpenLine + 1),
    ok = int:break(slate_dets_ffi, Line),
    ok = int:delete_break(slate_dets_ffi, OpenLine),
    {open_breakpoint, slate_dets_ffi, Line}.

info_line([Line | Rest], Number) ->
    %% Collisions are rejected at the reservation now, before reaching DETS.
    case binary:match(Line, <<"busy -> open_table">>) of
        nomatch -> info_line(Rest, Number + 1);
        _ -> Number
    end;
info_line([], _) ->
    erlang:error(collision_check_not_found).
