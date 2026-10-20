-module(corruption_test_ffi).
-export([truncate_file/2, corrupt_byte/2, get_file_size/1,
         with_temporary_file/1, corrupt_object/3]).

%% Scope cleanup even when a public Gleam traversal assertion raises.
with_temporary_file(Callback) ->
    Path = filename:absname("test_corrupt_object_" ++
        integer_to_list(erlang:unique_integer([positive, monotonic])) ++ ".dets"),
    try Callback(list_to_binary(Path))
    after
        [begin
            %% A corrupt table may report its storage error on close too;
            %% independently verify that no live server escaped the fixture.
            _ = dets:close(Name),
            undefined = dets:info(Name, pid)
         end || Name <- dets:all(), dets:info(Name, filename) =:= Path],
        case file:delete(Path) of
            ok -> ok;
            {error, enoent} -> ok
        end
    end.

%% Corrupt the actual external-term version byte, not a guessed file offset.
%% Call only after sync; a one-object fixture has exactly one matching term.
corrupt_object(Path, Key, Value) ->
    {ok, Bytes} = file:read_file(Path),
    [{Offset, _}] = binary:matches(Bytes, term_to_binary({Key, Value})),
    {ok, File} = file:open(Path, [raw, binary, read, write]),
    try
        ok = file:pwrite(File, Offset, <<130>>),
        ok = file:sync(File),
        {ok, nil}
    after
        ok = file:close(File)
    end.

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
