-module(with_table_ffi).
-export([with_close/3]).

%% Runs Fun(Resource), then Close(Resource), and returns the appropriate result.
%%
%% Close is expected to return {ok, _} | {error, _} (a Gleam Result), not raise.
%% If Fun raises, Close is attempted inside a catch (best-effort) and the
%% original exception is re-raised. If Close itself raises after Fun succeeds,
%% the callback's successful result is lost and the Close exception propagates;
%% this is acceptable because Gleam close functions return Result types and
%% should never raise under normal operation.
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
