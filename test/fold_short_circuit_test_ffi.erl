-module(fold_short_circuit_test_ffi).
-export([reset_counter/0, increment_counter/0, get_counter/0]).

reset_counter() ->
    put(slate_test_fold_counter, 0),
    nil.

increment_counter() ->
    Count = case get(slate_test_fold_counter) of
        undefined -> 0;
        N -> N
    end,
    put(slate_test_fold_counter, Count + 1),
    nil.

get_counter() ->
    case get(slate_test_fold_counter) of
        undefined -> 0;
        N -> N
    end.
