-module(path_test_ffi).
-export([delete_file/1]).

delete_file(Path) ->
    case file:delete(binary_to_list(Path)) of
        ok -> {ok, nil};
        {error, Reason} -> {error, Reason}
    end.
