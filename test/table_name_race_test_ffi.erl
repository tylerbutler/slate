-module(table_name_race_test_ffi).
-export([with_open_breakpoint/1, paused_openers/1, continue_open/1,
         disable_open_breakpoint/1, collision_check_breakpoint/1]).

%% gleam_erlang supplies all worker/message/monitor operations, but no debugger
%% API. Use a real OTP breakpoint, not sleeps or asynchronous trace/suspend,
%% to hold callers AFTER allocation and BEFORE DETS reserves the chosen name.
%% No production instrumentation or fake DETS responses are involved.
with_open_breakpoint(Callback) ->
    Source = filename:join(["src", "slate_dets_ffi.erl"]),
    {ok, Contents} = file:read_file(Source),
    Line = open_line(binary:split(Contents, <<"\n">>, [global]), 1),
    {module, slate_dets_ffi} = int:i(Source),
    try
        ok = int:break(slate_dets_ffi, Line),
        Callback({open_breakpoint, Line})
    after
        %% Release paused callers even if a Gleam assertion raises. Worker
        %% lifetimes are otherwise bounded by typed receives and links.
        int:no_break(slate_dets_ffi),
        [int:continue(Pid) || {Pid, _, break, _} <- int:snapshot()],
        ok = int:n(slate_dets_ffi),
        int:clear()
    end.

open_line([Line | Rest], Number) ->
    case binary:match(Line, <<"case dets:open_file(Name, Options) of">>) of
        nomatch -> open_line(Rest, Number + 1);
        _ -> Number
    end;
open_line([], _) ->
    erlang:error(dets_open_call_not_found).

paused_openers({open_breakpoint, Line}) ->
    [Pid || {Pid, _, break, {slate_dets_ffi, AtLine}} <- int:snapshot(),
            AtLine =:= Line].

continue_open(Pid) ->
    case int:continue(Pid) of
        ok -> {ok, nil};
        {error, _} -> {error, nil}
    end.

disable_open_breakpoint({open_breakpoint, Line}) ->
    ok = int:delete_break(slate_dets_ffi, Line),
    nil.

collision_check_breakpoint({open_breakpoint, OpenLine}) ->
    {ok, Contents} = file:read_file(filename:join(["src", "slate_dets_ffi.erl"])),
    Lines = lists:nthtail(OpenLine, binary:split(Contents, <<"\n">>, [global])),
    Line = info_line(Lines, OpenLine + 1),
    ok = int:break(slate_dets_ffi, Line),
    ok = int:delete_break(slate_dets_ffi, OpenLine),
    {open_breakpoint, Line}.

info_line([Line | Rest], Number) ->
    case binary:match(Line, <<"case dets:info(Name, filename) of">>) of
        nomatch -> info_line(Rest, Number + 1);
        _ -> Number
    end;
info_line([], _) ->
    erlang:error(collision_check_not_found).
