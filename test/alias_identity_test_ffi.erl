-module(alias_identity_test_ffi).
-include_lib("kernel/include/file.hrl").
-export([with_alias/2, hard_link/2, replaced/2, with_raw/2, track_worker/1]).

%% Only fixture operations live here. Opens, writes, reads, and close/reopen
%% assertions use the public Gleam API, not a second implementation of it.
with_alias(Kind, Callback) ->
    case os:type() of
        {win32, _} -> nil; % Ordinary Windows opens remain identity-unprotected.
        {unix, _} ->
            Root = filename:absname("test_alias_" ++
                integer_to_list(erlang:unique_integer([positive, monotonic]))),
            ok = file:make_dir(Root),
            Previous = put(?MODULE, []),
            try
                case fixture(Kind, Root) of
                    unsupported -> nil;
                    {First, Second} ->
                        Callback(list_to_binary(First), list_to_binary(Second))
                end
            after
                Workers = get(?MODULE),
                case Previous of
                    undefined -> erase(?MODULE);
                    _ -> put(?MODULE, Previous)
                end,
                %% Join workers and real DETS PIDs even on assertion failure.
                Tables = [Name || Name <- dets:all(),
                    under_root(dets:info(Name, filename), Root)],
                Pids = [Pid || Name <- Tables,
                    Pid <- [dets:info(Name, owner)], is_pid(Pid)],
                lists:foreach(fun(Pid) -> exit(Pid, kill), await_down(Pid) end, Workers),
                [_ = dets:close(Name) || Name <- Tables],
                lists:foreach(fun await_down/1, Pids),
                ok = file:del_dir_r(Root)
            end
    end.

under_root(undefined, _) -> false;
under_root(Path, Root) when is_binary(Path) -> under_root(binary_to_list(Path), Root);
under_root(Path, Root) -> lists:prefix(Root ++ "/", Path).

await_down(Pid) ->
    Ref = monitor(process, Pid),
    try
        receive {'DOWN', Ref, process, Pid, _} -> ok
        after 5000 -> error({alias_fixture_process_still_alive, Pid})
        end
    after demonitor(Ref, [flush])
    end.

track_worker(Pid) ->
    Workers = get(?MODULE),
    true = is_list(Workers),
    put(?MODULE, [Pid | Workers]),
    nil.

fixture(Kind, Root) ->
    First = filename:join(Root, "table.dets"),
    Second = filename:join(Root, "alias.dets"),
    case Kind of
        hard_link ->
            seed(First),
            ok = file:make_link(First, Second),
            {First, Second};
        unclean_hard_link ->
            seed_unclean(First),
            ok = file:make_link(First, Second),
            {First, Second};
        existing_file_symlink ->
            seed(First),
            ok = file:make_symlink("table.dets", Second),
            {First, Second};
        missing_file_symlink ->
            ok = file:make_symlink("table.dets", Second),
            {First, Second};
        existing_directory_symlink -> directory_alias(Root, true);
        missing_directory_symlink -> directory_alias(Root, false);
        symlink_parent ->
            Deep = filename:join([Root, "real", "deep"]),
            ok = filelib:ensure_dir(filename:join(Deep, "unused")),
            ok = file:make_symlink("real/deep", filename:join(Root, "link")),
            {filename:join([Root, "real", "table.dets"]),
             filename:join([Root, "link", "..", "table.dets"])};
        existing_case_leaf -> case_alias(Root, true, leaf);
        missing_case_leaf -> case_alias(Root, false, leaf);
        case_parent -> case_alias(Root, false, parent)
    end.

directory_alias(Root, Existing) ->
    ok = file:make_dir(filename:join(Root, "real")),
    ok = file:make_symlink("real", filename:join(Root, "link")),
    First = filename:join([Root, "real", "table.dets"]),
    case Existing of true -> seed(First); false -> ok end,
    {First, filename:join([Root, "link", "table.dets"])}.

case_alias(Root, Existing, Part) ->
    Parent = filename:join(Root, "Parent"),
    ok = file:make_dir(Parent),
    %% Query the filesystem rather than infer case behavior from os:type().
    case file:read_file_info(filename:join(Root, "pARENT")) of
        {error, enoent} -> unsupported;
        {ok, _} ->
            First = filename:join(Parent, "table.dets"),
            case Existing of true -> seed(First); false -> ok end,
            Second = case Part of
                parent -> filename:join([Root, "pARENT", "table.dets"]);
                leaf -> filename:join(Parent, "TABLE.dets")
            end,
            {First, Second}
    end.

seed(Path) ->
    {ok, alias_identity_seed} = dets:open_file(alias_identity_seed, [{file, Path}]),
    ok = dets:close(alias_identity_seed).

seed_unclean(Path) ->
    %% Copy a real dirty DETS file, without guessing version-specific header
    %% offsets or crashing the test VM. Disable timed writes during the copy.
    {ok, alias_identity_seed} = dets:open_file(alias_identity_seed,
        [{file, Path}, {auto_save, infinity}, {delayed_write, {0, 0}}]),
    Snapshot = Path ++ ".dirty",
    try
        ok = dets:insert(alias_identity_seed, {<<"seed">>, 1}),
        ok = dets:sync(alias_identity_seed),
        ok = dets:insert(alias_identity_seed, {<<"seed">>, 1}),
        {ok, _} = file:copy(Path, Snapshot)
    after ok = dets:close(alias_identity_seed)
    end,
    ok = file:rename(Snapshot, Path).

hard_link(First, Second) ->
    ok = file:make_link(binary_to_list(First), binary_to_list(Second)),
    nil.

replaced(First, Second) ->
    {ok, A} = file:read_file_info(First),
    {ok, B} = file:read_file_info(Second),
    true = A#file_info.inode > 0,
    true = B#file_info.inode > 0,
    {A#file_info.major_device, A#file_info.minor_device, A#file_info.inode} =/=
        {B#file_info.major_device, B#file_info.minor_device, B#file_info.inode}.

with_raw(Path, Callback) ->
    {ok, alias_identity_raw} =
        dets:open_file(alias_identity_raw, [{file, binary_to_list(Path)}]),
    try Callback() of
        Result ->
            ok = dets:close(alias_identity_raw),
            Result
    catch
        Class:Reason:Stack ->
            %% A double-writer regression can make cleanup report corruption.
            %% Keep the original public API assertion as the primary failure.
            _ = dets:close(alias_identity_raw),
            erlang:raise(Class, Reason, Stack)
    end.
