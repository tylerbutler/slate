-module(dets_ffi).
-export([
    open_set/2, open_bag/2, open_duplicate_bag/2,
    open_set_with_access/3, open_bag_with_access/3, open_duplicate_bag_with_access/3,
    close/1, insert/2, insert_new/2, insert_new_object/2,
    lookup/2, lookup_all/2, delete_key/2, delete_object/2, delete_all/1,
    member/2, sync/1, fold/3, to_list/1,
    info_size/1, info_file_size/1,
    is_dets_file/1, update_counter/3,
    canonicalize_path/1
]).

-define(TABLE_NAME_POOL_SIZE, 4096).

%% ── Open ────────────────────────────────────────────────────────────────

open_set(Path, Repair) ->
    do_open(Path, set, Repair, read_write).

open_bag(Path, Repair) ->
    do_open(Path, bag, Repair, read_write).

open_duplicate_bag(Path, Repair) ->
    do_open(Path, duplicate_bag, Repair, read_write).

open_set_with_access(Path, Repair, Access) ->
    do_open(Path, set, Repair, Access).

open_bag_with_access(Path, Repair, Access) ->
    do_open(Path, bag, Repair, Access).

open_duplicate_bag_with_access(Path, Repair, Access) ->
    do_open(Path, duplicate_bag, Repair, Access).

do_open(Path, Type, Repair, Access) ->
    try
        CanonicalPath = canonicalize_path(Path),
        Name = table_name_for_path(CanonicalPath),
        RepairVal = repair_value(Repair),
        AccessVal = access_value(Access),
        Opts = [{file, CanonicalPath}, {type, Type}, {repair, RepairVal}, {access, AccessVal}],
        case dets:open_file(Name, Opts) of
            {ok, Name} -> {ok, Name};
            {error, OpenReason} -> {error, translate_error(OpenReason)}
        end
    catch
        _:CatchReason -> {error, translate_error(CatchReason)}
    end.

%% Gleam RepairPolicy constructors map to these atoms:
%%   auto_repair -> true, force_repair -> force, no_repair -> false
repair_value(auto_repair) -> true;
repair_value(force_repair) -> force;
repair_value(no_repair) -> false.

%% Gleam AccessMode constructors:
%%   read_write -> read_write, read_only -> read
access_value(read_write) -> read_write;
access_value(read_only) -> read.

canonicalize_path(Path) when is_binary(Path) ->
    filename:absname(binary_to_list(Path));
canonicalize_path(Path) when is_list(Path) ->
    filename:absname(Path).

table_name_for_path(CanonicalPath) ->
    case find_open_table_for_path(CanonicalPath) of
        {ok, Name} -> Name;
        error -> allocate_table_name(CanonicalPath)
    end.

find_open_table_for_path(CanonicalPath) ->
    find_open_table_for_path(dets:all(), CanonicalPath).

find_open_table_for_path([], _CanonicalPath) ->
    error;
find_open_table_for_path([Name | Rest], CanonicalPath) ->
    case dets:info(Name, filename) of
        undefined ->
            find_open_table_for_path(Rest, CanonicalPath);
        OpenPath ->
            case canonicalize_path(OpenPath) of
                CanonicalPath -> {ok, Name};
                _ -> find_open_table_for_path(Rest, CanonicalPath)
            end
    end.

allocate_table_name(CanonicalPath) ->
    Start = erlang:phash2(CanonicalPath, ?TABLE_NAME_POOL_SIZE),
    allocate_table_name(CanonicalPath, Start, 0).

allocate_table_name(_CanonicalPath, _Start, Attempts) when Attempts >= ?TABLE_NAME_POOL_SIZE ->
    %% Caught by the try-catch in do_open/4; translate_error/1 maps this
    %% to table_name_pool_exhausted (TableNamePoolExhausted in Gleam).
    erlang:error(no_available_table_name);
allocate_table_name(CanonicalPath, Start, Attempts) ->
    Index = (Start + Attempts) rem ?TABLE_NAME_POOL_SIZE,
    Name = table_name_atom(Index),
    case dets:info(Name, filename) of
        undefined ->
            Name;
        OpenPath ->
            case canonicalize_path(OpenPath) of
                CanonicalPath -> Name;
                _ -> allocate_table_name(CanonicalPath, Start, Attempts + 1)
            end
    end.

table_name_atom(Index) ->
    %% Bounded atom creation: creates at most TABLE_NAME_POOL_SIZE atoms.
    list_to_atom("slate_dets_" ++ integer_to_list(Index)).

%% ── Close / Sync ───────────────────────────────────────────────────────

close(Name) ->
    try dets:close(Name) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

sync(Name) ->
    try dets:sync(Name) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Insert ──────────────────────────────────────────────────────────────

insert(Name, Objects) ->
    try dets:insert(Name, Objects) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

insert_new(Name, Objects) ->
    try dets:insert_new(Name, Objects) of
        true -> {ok, nil};
        false -> {error, key_already_present};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% For bag tables: rejects duplicate key-value pairs but allows same key
%% with different values. Checks if the exact object already exists via
%% dets:match_object before inserting.
insert_new_object(Name, Object) ->
    try dets:match_object(Name, Object) of
        [] ->
            insert(Name, Object);
        [_ | _] ->
            {error, key_already_present};
        {error, Reason} ->
            {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Lookup ──────────────────────────────────────────────────────────────

%% For set tables: returns single value or not_found.
lookup(Name, Key) ->
    try dets:lookup(Name, Key) of
        [] -> {error, not_found};
        [{_, Value} | _] -> {ok, Value};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% For bag/duplicate_bag tables: returns list of values.
lookup_all(Name, Key) ->
    try dets:lookup(Name, Key) of
        Results when is_list(Results) ->
            Values = [V || {_, V} <- Results],
            {ok, Values};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Delete ──────────────────────────────────────────────────────────────

delete_key(Name, Key) ->
    try dets:delete(Name, Key) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

delete_object(Name, Object) ->
    try dets:delete_object(Name, Object) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

delete_all(Name) ->
    try dets:delete_all_objects(Name) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Query ───────────────────────────────────────────────────────────────

member(Name, Key) ->
    try dets:member(Name, Key) of
        true -> {ok, true};
        false -> {ok, false};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

fold(Name, Fun, Acc0) ->
    WrappedFun = fun(Entry, Acc) ->
        case Fun(Entry, Acc) of
            {error, _} = Err -> throw({slate_fold_abort, Err});
            Result -> Result
        end
    end,
    try dets:foldl(WrappedFun, Acc0, Name) of
        Result -> {ok, Result}
    catch
        throw:{slate_fold_abort, Err} -> {ok, Err};
        _:Reason -> {error, translate_error(Reason)}
    end.

to_list(Name) ->
    try dets:foldl(fun(Obj, Acc) -> [Obj | Acc] end, [], Name) of
        Result -> {ok, Result}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Info ────────────────────────────────────────────────────────────────

info_size(Name) ->
    info_integer(Name, size).

info_file_size(Name) ->
    info_integer(Name, file_size).

info_integer(Name, Item) ->
    try dets:info(Name, Item) of
        undefined -> {error, table_does_not_exist};
        Value when is_integer(Value) -> {ok, Value};
        Other -> {error, unexpected_error({dets_info, Item, Other})}
    catch
        error:Reason -> {error, translate_error(Reason)}
    end.

%% ── Utilities ───────────────────────────────────────────────────────────

is_dets_file(Path) ->
    try dets:is_dets_file(binary_to_list(Path)) of
        true -> {ok, true};
        false -> {ok, false};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

update_counter(Name, Key, Increment) ->
    try dets:update_counter(Name, Key, Increment) of
        NewVal when is_integer(NewVal) -> {ok, NewVal};
        {error, Reason} -> {error, translate_error(Reason)};
        Other -> {error, unexpected_error({update_counter, Other})}
    catch
        error:badarg -> classify_update_counter_badarg(Name, Key);
        error:Reason -> {error, translate_error(Reason)}
    end.

classify_update_counter_badarg(Name, Key) ->
    case info_integer(Name, size) of
        {error, table_does_not_exist} ->
            {error, table_does_not_exist};
        {ok, _} ->
            classify_update_counter_lookup(Name, Key);
        {error, Reason} ->
            {error, Reason}
    end.

classify_update_counter_lookup(Name, Key) ->
    try dets:lookup(Name, Key) of
        [] ->
            {error, not_found};
        [{_, Value} | _] when is_integer(Value) ->
            {error, unexpected_error(update_counter_badarg)};
        [{_, _} | _] ->
            {error, {erlang_error, <<"update_counter requires an integer value">>}};
        Other ->
            {error, unexpected_error({update_counter_lookup, Other})}
    catch
        error:Reason -> {error, translate_error(Reason)}
    end.

%% ── Error translation ──────────────────────────────────────────────────
%% Maps Erlang DETS errors to atoms matching Gleam DetsError constructors.

translate_error(not_found) -> not_found;
translate_error(key_already_present) -> key_already_present;
translate_error({file_error, _, enoent}) -> file_not_found;
translate_error({file_error, _, eacces}) -> access_denied;
translate_error({file_error, _, {error, eacces}}) -> access_denied;
translate_error({file_error, _, {error, einval}}) -> access_denied;
translate_error({access_mode, _}) -> access_denied;
translate_error({type_mismatch, _}) -> type_mismatch;
translate_error({keypos_mismatch, _}) -> type_mismatch;
translate_error({incompatible_arguments, _}) -> already_open;
translate_error(incompatible_arguments) -> already_open;
translate_error(badarg) -> table_does_not_exist;
translate_error({file_error, _, efbig}) -> file_size_limit_exceeded;
translate_error(no_available_table_name) -> table_name_pool_exhausted;
translate_error({error, Reason}) -> translate_error(Reason);
translate_error({Reason, _Context}) -> translate_error(Reason);
translate_error(Reason) ->
    unexpected_error(Reason).

unexpected_error(Reason) ->
    {erlang_error, list_to_binary(io_lib:format("~p", [Reason]))}.
