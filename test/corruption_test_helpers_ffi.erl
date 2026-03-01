-module(corruption_test_helpers_ffi).
-export([write_garbage/1, truncate_file_create/1]).

%% Write 100 bytes of garbage to a file (simulates a non-DETS file).
write_garbage(Path) ->
    PathStr = binary_to_list(Path),
    Data = list_to_binary(lists:duplicate(100, 65)),
    case file:write_file(PathStr, Data) of
        ok -> {ok, nil};
        {error, _} -> {error, nil}
    end.

%% Create an empty (0 byte) file.
truncate_file_create(Path) ->
    PathStr = binary_to_list(Path),
    case file:open(PathStr, [write]) of
        {ok, Fd} ->
            ok = file:close(Fd),
            {ok, nil};
        {error, _} ->
            {error, nil}
    end.
