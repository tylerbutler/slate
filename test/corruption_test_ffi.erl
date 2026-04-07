-module(corruption_test_ffi).
-export([truncate_file/2, corrupt_byte/2, get_file_size/1]).

%% Truncate a file at the given byte position.
truncate_file(Path, Where) ->
    PathStr = binary_to_list(Path),
    case file:open(PathStr, [read, write, binary]) of
        {ok, Fd} ->
            file:position(Fd, Where),
            ok = file:truncate(Fd),
            ok = file:close(Fd),
            {ok, nil};
        {error, _Reason} ->
            {error, nil}
    end.

%% Corrupt a single byte at the given position.
corrupt_byte(Path, Where) ->
    PathStr = binary_to_list(Path),
    case file:open(PathStr, [read, write, binary]) of
        {ok, Fd} ->
            case file:pread(Fd, Where, 1) of
                {ok, <<Byte>>} ->
                    ok = file:pwrite(Fd, Where, <<(Byte bxor 1)>>),
                    ok = file:close(Fd),
                    {ok, nil};
                _ ->
                    ok = file:close(Fd),
                    {error, nil}
            end;
        {error, _Reason} ->
            {error, nil}
    end.

%% Get the size of a file in bytes.
get_file_size(Path) ->
    PathStr = binary_to_list(Path),
    case file:read_file_info(PathStr) of
        {ok, Info} ->
            {ok, element(2, Info)};
        {error, _Reason} ->
            {error, nil}
    end.
