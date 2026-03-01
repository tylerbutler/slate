-module(is_dets_file_test_ffi).
-export([write_file/2]).

write_file(Path, Content) ->
    case file:write_file(binary_to_list(Path), Content) of
        ok -> {ok, nil};
        {error, _Reason} -> {error, nil}
    end.
