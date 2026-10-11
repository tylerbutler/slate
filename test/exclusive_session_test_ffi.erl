-module(exclusive_session_test_ffi).
-export([begin_trace/0, end_trace/1, raise_original/0, raise_cleanup/0,
         check_original_exception/1]).

begin_trace() ->
    Caller = self(),
    Tracer = spawn(fun() -> trace_loop(Caller, true) end),
    1 = erlang:trace(Caller, true, [send, 'receive', {tracer, Tracer}]),
    {ok, Tracer}.

end_trace(Tracer) ->
    1 = erlang:trace(self(), false, [send, 'receive']),
    Delivery = erlang:trace_delivered(self()),
    receive {trace_delivered, _, Delivery} -> ok after 5000 -> error(trace_timeout) end,
    Tracer ! finish,
    receive {Tracer, Result} -> Result after 5000 -> error(tracer_timeout) end.

trace_loop(Caller, Safe) ->
    receive
        {trace, Caller, send, Message, _} ->
            trace_loop(Caller, Safe andalso not contains_payload(Message));
        {trace, Caller, 'receive', Message} ->
            trace_loop(Caller, Safe andalso not contains_payload(Message));
        finish -> Caller ! {self(), Safe}
    end.

contains_payload({callback_value, _, _}) -> true;
contains_payload({?MODULE, original_callback, 0, _}) -> true;
contains_payload(Tuple) when is_tuple(Tuple) ->
    lists:any(fun contains_payload/1, tuple_to_list(Tuple));
contains_payload(List) when is_list(List) ->
    lists:any(fun contains_payload/1, List);
contains_payload(_) -> false.

raise_original() ->
    %% Known stack and an arbitrary reason exercise re-raise, not recreation.
    erlang:raise(error, {original_exception, [1, 2, 3]},
                 [{?MODULE, original_callback, 0, [{file, "original_callback.erl"}, {line, 42}]}]).

raise_cleanup() -> throw(different_cleanup_exception).

check_original_exception(Callback) ->
    try Callback() of
        _ -> false
    catch
        error:{original_exception, [1, 2, 3]}:Stack ->
            Stack =:= [{?MODULE, original_callback, 0,
                        [{file, "original_callback.erl"}, {line, 42}]}]
    end.
