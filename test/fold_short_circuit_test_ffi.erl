-module(fold_short_circuit_test_ffi).
-export([count_ffi_fold_invocations/1, check_exception_preservation/1]).

check_exception_preservation(Run) ->
    lists:foreach(fun(Class) ->
        Reason = {callback_failure, make_ref()},
        Stack = [{?MODULE, original_callback, 0, [{line, 123}]}],
        try Run(fun() -> erlang:raise(Class, Reason, Stack) end) of
            Returned -> error({callback_exception_swallowed, Returned})
        catch
            Class:Reason:ActualStack -> Stack = ActualStack;
            OtherClass:OtherReason:OtherStack ->
                error({callback_exception_changed, OtherClass, OtherReason, OtherStack})
        end
    end, [error, exit, throw]),
    nil.

count_ffi_fold_invocations({_Type, TableReference, _KeyDecoder, _ValueDecoder}) ->
    put(ffi_fold_counter, 0),
    Callback = fun(_Entry, _Accumulator) ->
        put(ffi_fold_counter, get(ffi_fold_counter) + 1),
        {error, decode_error}
    end,
    slate_dets_ffi:fold(TableReference, Callback, ok),
    get(ffi_fold_counter).
