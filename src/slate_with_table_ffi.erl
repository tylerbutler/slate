-module(slate_with_table_ffi).
-export([capture/1, reraise/1]).

%% Gleam cannot catch arbitrary Erlang exception classes or retain the original
%% stack. These opaque exceptions never leave the callback's process.
capture(Callback) ->
    try Callback() of
        Value -> {returned, Value}
    catch
        Class:Reason:Stack ->
            {raised, {exception, Class, Reason, Stack}, {Class, Reason}}
    end.

reraise({exception, Class, Reason, Stack}) ->
    erlang:raise(Class, Reason, Stack).
