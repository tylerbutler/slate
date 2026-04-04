-module(fold_short_circuit_test_ffi).
-export([count_ffi_fold_invocations/1]).

count_ffi_fold_invocations({_Type, TableRef, _KeyDec, _ValDec}) ->
    put(ffi_fold_counter, 0),
    Fun = fun(_Entry, _Acc) ->
        put(ffi_fold_counter, get(ffi_fold_counter) + 1),
        {error, decode_error}
    end,
    dets_ffi:fold(TableRef, Fun, ok),
    get(ffi_fold_counter).
