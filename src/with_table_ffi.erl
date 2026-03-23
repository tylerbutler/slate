-module(with_table_ffi).
-export([with_close/3]).

with_close(Resource, Fun, Close) ->
    try
        CallbackResult = Fun(Resource),
        CloseResult = Close(Resource),
        finalize_with_close(CallbackResult, CloseResult)
    catch
        Class:Reason:Stacktrace ->
            _ = catch Close(Resource),
            erlang:raise(Class, Reason, Stacktrace)
    end.

finalize_with_close({ok, Value}, {ok, _}) ->
    {ok, Value};
finalize_with_close({ok, _}, {error, _} = CloseError) ->
    CloseError;
finalize_with_close({error, _} = CallbackError, _) ->
    CallbackError.
