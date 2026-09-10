-module(fold_short_circuit_test_ffi).
-export([count_ffi_fold_invocations/1]).

count_ffi_fold_invocations({_Type, TableReference, _KeyDecoder, _ValueDecoder}) ->
    put(ffi_fold_counter, 0),
    Callback = fun(_Entry, _Accumulator) ->
        put(ffi_fold_counter, get(ffi_fold_counter) + 1),
        {error, decode_error}
    end,
    slate_dets_ffi:fold(TableReference, Callback, ok),
    get(ffi_fold_counter).
