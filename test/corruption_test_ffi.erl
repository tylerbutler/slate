-module(corruption_test_ffi).
-export([truncate_file/2, corrupt_byte/2, get_file_size/1]).

%% Truncate a file at the given byte position.
truncate_file(Path, Where) ->
    PathString = binary_to_list(Path),
    case file:open(PathString, [read, write, binary]) of
        {ok, FileDescriptor} ->
            file:position(FileDescriptor, Where),
            ok = file:truncate(FileDescriptor),
            ok = file:close(FileDescriptor),
            {ok, nil};
        {error, _Reason} ->
            {error, nil}
    end.

%% Corrupt a single byte at the given position.
corrupt_byte(Path, Where) ->
    PathString = binary_to_list(Path),
    case file:open(PathString, [read, write, binary]) of
        {ok, FileDescriptor} ->
            case file:pread(FileDescriptor, Where, 1) of
                {ok, <<Byte>>} ->
                    ok = file:pwrite(FileDescriptor, Where, <<(Byte bxor 1)>>),
                    ok = file:close(FileDescriptor),
                    {ok, nil};
                _ ->
                    ok = file:close(FileDescriptor),
                    {error, nil}
            end;
        {error, _Reason} ->
            {error, nil}
    end.

%% Get the size of a file in bytes.
get_file_size(Path) ->
    PathString = binary_to_list(Path),
    case file:read_file_info(PathString) of
        {ok, Info} ->
            {ok, element(2, Info)};
        {error, _Reason} ->
            {error, nil}
    end.
