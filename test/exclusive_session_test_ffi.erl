-module(exclusive_session_test_ffi).
-export([with_trace/1, current_tracer/0, trace_is_clean/1,
         check_assertion_exception/1, raise_original/0, raise_cleanup/0,
         check_original_exception/1]).

%% This test-only scope owns the caller's legacy trace flags. Do not replace
%% another tracer (or allow nested scopes). Callback values stay in the caller.
with_trace(Callback) ->
    Caller = self(),
    {flags, []} = erlang:trace_info(Caller, flags),
    {Tracer, Monitor} = spawn_monitor(fun() ->
        OwnerMonitor = monitor(process, Caller),
        trace_loop(Caller, OwnerMonitor, none, true)
    end),
    Outcome = try
        1 = erlang:trace(Caller, true, [send, 'receive', {tracer, Tracer}]),
        Value = Callback(),
        1 = erlang:trace(Caller, false, [send, 'receive']),
        Tracer ! {finish, Caller},
        receive
            {'DOWN', Monitor, process, Tracer, {trace_result, Safe}} ->
                {returned, {Value, Safe}};
            {'DOWN', Monitor, process, Tracer, Reason} ->
                error({tracer_failed, Reason})
        after 5000 ->
            error(tracer_timeout)
        end
    catch
        Class:Exception:Stack -> {raised, Class, Exception, Stack}
    end,
    1 = erlang:trace(Caller, false, [send, 'receive']),
    Cleanup = stop_tracer(Tracer, Monitor),
    case {Outcome, Cleanup} of
        {{returned, Result}, ok} -> Result;
        {{returned, _}, {error, Failure}} -> error(Failure);
        {{raised, OriginalClass, OriginalReason, OriginalStack}, _} ->
            case Cleanup of
                ok -> ok;
                {error, Failure} ->
                    %% A cleanup failure must not replace the original stack.
                    logger:error("Trace cleanup failed: ~p", [Failure])
            end,
            erlang:raise(OriginalClass, OriginalReason, OriginalStack)
    end.

stop_tracer(Tracer, Monitor) ->
    %% The result receive may already have consumed the original DOWN. A fresh
    %% monitor lets both paths confirm termination without waiting twice for it.
    Shutdown = monitor(process, Tracer),
    exit(Tracer, kill),
    try
        receive
            {'DOWN', Shutdown, process, Tracer, _} -> ok
        after 5000 ->
            {error, {tracer_cleanup_timeout, Tracer}}
        end
    after
        demonitor(Shutdown, [flush]),
        demonitor(Monitor, [flush])
    end.

trace_loop(Caller, OwnerMonitor, Delivery, Safe) ->
    receive
        {trace, Caller, send, Message, _} ->
            trace_loop(Caller, OwnerMonitor, Delivery,
                       Safe andalso not contains_payload(Message));
        {trace, Caller, 'receive', Message} ->
            trace_loop(Caller, OwnerMonitor, Delivery,
                       Safe andalso not contains_payload(Message));
        {finish, Caller} when Delivery =:= none ->
            %% Keep the delivery marker here, not in the shared test caller.
            %% Even a timeout/kill cannot leave a late marker in that caller.
            Reference = erlang:trace_delivered(Caller),
            trace_loop(Caller, OwnerMonitor, Reference, Safe);
        {trace_delivered, Caller, Delivery} when is_reference(Delivery) ->
            %% The monitor is the only reply channel: it also proves exit.
            exit({trace_result, Safe});
        {'DOWN', OwnerMonitor, process, Caller, _} ->
            ok
    end.

current_tracer() ->
    {tracer, Tracer} = erlang:trace_info(self(), tracer),
    true = is_pid(Tracer),
    Tracer.

trace_is_clean(Tracer) ->
    Caller = self(),
    {messages, Messages} = process_info(Caller, messages),
    {monitors, Monitors} = process_info(Caller, monitors),
    erlang:trace_info(Caller, flags) =:= {flags, []}
        andalso not is_process_alive(Tracer)
        andalso not lists:member({process, Tracer}, Monitors)
        andalso not lists:any(fun
            ({'DOWN', _, process, Process, _}) when Process =:= Tracer -> true;
            ({Process, _}) when Process =:= Tracer -> true;
            ({trace_delivered, Process, _}) when Process =:= Caller -> true;
            (_) -> false
        end, Messages).

check_assertion_exception(Callback) ->
    try Callback() of
        _ -> false
    catch
        error:#{gleam_error := assert} -> true
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
