-module(slate_dets_ffi).
-export([
    open_set/2, open_bag/2, open_duplicate_bag/2,
    open_set_with_access/3, open_bag_with_access/3, open_duplicate_bag_with_access/3,
    close/1, insert/2, insert_new/2, insert_new_object/2,
    lookup/2, lookup_all/2, delete_key/2, delete_object/2, delete_all/1,
    member/2, sync/1, fold/3, to_list/1,
    info_size/1, info_file_size/1, info_path/1,
    is_dets_file/1, update_counter/3,
    canonicalize_path/1, translate_error/1
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
        RepairValue = repair_value(Repair),
        AccessValue = access_value(Access),
        Options = [{file, CanonicalPath}, {type, Type}, {repair, RepairValue}, {access, AccessValue}],
        case dets:open_file(Name, Options) of
            {ok, Name} -> {ok, Name};
            {error, incompatible_arguments} ->
                %% OTP omits the filename for conflicting open options.
                {error, contextual_file_error(already_open, CanonicalPath, incompatible_arguments)};
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
    normalize_path(filename:absname(binary_to_list(Path)));
canonicalize_path(Path) when is_list(Path) ->
    normalize_path(filename:absname(Path)).

%% Collapse "." and ".." segments so that "./foo.dets" and "../cwd/foo.dets"
%% resolve to the same canonical path.  Does NOT follow symlinks (the file
%% may not exist yet).
normalize_path(AbsolutePath) ->
    Parts = filename:split(AbsolutePath),
    filename:join(normalize_parts(Parts, [])).

normalize_parts([], Acc) -> lists:reverse(Acc);
normalize_parts(["." | Rest], Acc) -> normalize_parts(Rest, Acc);
normalize_parts([".." | Rest], [_ | Acc]) -> normalize_parts(Rest, Acc);
normalize_parts([".." | Rest], []) -> normalize_parts(Rest, []);
normalize_parts([Part | Rest], Acc) -> normalize_parts(Rest, [Part | Acc]).

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
%%
%% NOTE: This is NOT atomic. Between the match_object check and the insert,
%% another process could insert the same object. In practice the window is
%% tiny and the consequence is benign: both callers succeed, but DETS's own
%% bag deduplication ensures only one copy ends up in the table.
%% We cannot use dets:insert_new/2 here because it checks by KEY only,
%% whereas bag insert_new needs to check the exact KEY+VALUE pair.
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
            Values = [Value || {_, Value} <- Results],
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

fold(Name, Callback, Initial) ->
    AbortTag = make_ref(),
    CallbackExceptionTag = make_ref(),
    WrappedCallback = fun(Entry, Acc) ->
        try Callback(Entry, Acc) of
            {error, _} = Error -> throw({AbortTag, Error});
            Result -> Result
        catch
            Class:Reason:Stacktrace ->
                throw({CallbackExceptionTag, Class, Reason, Stacktrace})
        end
    end,
    try dets:foldl(WrappedCallback, Initial, Name) of
        Result -> {ok, Result}
    catch
        throw:{AbortTag, Error} -> {ok, Error};
        throw:{CallbackExceptionTag, Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace);
        error:Reason -> {error, translate_error(Reason)};
        exit:Reason -> {error, translate_error(Reason)};
        throw:Reason -> {error, translate_error(Reason)}
    end.

to_list(Name) ->
    try dets:foldl(fun(Object, Acc) -> [Object | Acc] end, [], Name) of
        Result -> {ok, Result}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Info ────────────────────────────────────────────────────────────────

info_size(Name) ->
    info_integer(Name, size).

info_file_size(Name) ->
    info_integer(Name, file_size).

info_path(Name) ->
    try dets:info(Name, filename) of
        undefined -> {error, table_does_not_exist};
        Path when is_list(Path) ->
            %% canonicalize_path/1 supplies UTF-8 bytes, not codepoints.
            {ok, list_to_binary(Path)};
        Path when is_binary(Path) -> {ok, Path};
        Other -> {error, unexpected_error({dets_info, filename, Other})}
    catch
        error:Reason -> {error, translate_error(Reason)}
    end.

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
        NewValue when is_integer(NewValue) -> {ok, NewValue};
        {error, Reason} -> {error, update_counter_table_error(Reason)};
        Other -> {error, update_counter_table_error({update_counter, Other})}
    catch
        error:badarg -> classify_update_counter_badarg(Name, Key);
        error:Reason -> {error, update_counter_table_error(Reason)}
    end.

classify_update_counter_badarg(Name, Key) ->
    case info_integer(Name, size) of
        {error, table_does_not_exist} ->
            {error, update_counter_translated_error(table_does_not_exist)};
        {ok, _} ->
            classify_update_counter_lookup(Name, Key);
        {error, Reason} ->
            {error, update_counter_translated_error(Reason)}
    end.

classify_update_counter_lookup(Name, Key) ->
    try dets:lookup(Name, Key) of
        [] ->
            {error, update_counter_translated_error(not_found)};
        [{_, Value} | _] when is_integer(Value) ->
            {error, update_counter_table_error(update_counter_badarg)};
        [{_, _} | _] ->
            {error, ffi_counter_value_not_integer};
        Other ->
            {error, update_counter_table_error({update_counter_lookup, Other})}
    catch
        error:Reason -> {error, update_counter_table_error(Reason)}
    end.

update_counter_table_error(Reason) ->
    {ffi_table_error, translate_error(Reason)}.

update_counter_translated_error(Reason) ->
    {ffi_table_error, Reason}.

%% ── Error translation ──────────────────────────────────────────────────
%% Internal translation shared by every operation (also exercised by tests).
%% Gleam payload variants are tuples; Option(String) is none | {some, Binary}.

translate_error(not_found) -> not_found;
translate_error(key_already_present) -> key_already_present;
translate_error(not_a_dets_file) ->
    contextual_error(not_a_dets_file, none, not_a_dets_file);
translate_error(needs_repair) ->
    contextual_error(needs_repair, none, needs_repair);
translate_error({file_error, Path, Reason} = Error) ->
    case file_error_kind(Reason) of
        unexpected -> unexpected_error(Error);
        Kind -> contextual_file_error(Kind, Path, Reason)
    end;
translate_error({access_mode, Path}) ->
    contextual_file_error(access_denied, Path, access_mode);
translate_error({type_mismatch, Path}) ->
    contextual_file_error(type_mismatch, Path, type_mismatch);
translate_error({keypos_mismatch, Path}) ->
    contextual_file_error(type_mismatch, Path, keypos_mismatch);
translate_error({incompatible_arguments, Path}) when is_binary(Path); is_list(Path) ->
    contextual_file_error(already_open, Path, incompatible_arguments);
translate_error({incompatible_arguments, Context}) ->
    contextual_error(already_open, none, {incompatible_arguments, Context});
translate_error(incompatible_arguments) ->
    contextual_error(already_open, none, incompatible_arguments);
translate_error(badarg) -> table_does_not_exist;
translate_error({no_such_table, _}) -> table_does_not_exist;
translate_error({no_more_space_on_file, Path}) ->
    contextual_file_error(file_size_limit_exceeded, Path, no_more_space_on_file);
translate_error(no_available_table_name) -> table_name_pool_exhausted;
translate_error({not_a_dets_file, Path}) ->
    contextual_file_error(not_a_dets_file, Path, not_a_dets_file);
translate_error({needs_repair, Path}) ->
    contextual_file_error(needs_repair, Path, needs_repair);
translate_error({error, Reason}) -> translate_error(Reason);
translate_error({Reason, _Context}) -> translate_error(Reason);
translate_error(Reason) ->
    unexpected_error(Reason).

%% Unwrap only the known OTP error envelope for classification. Keep the
%% original reason in the context, including nested {error, Reason} tuples.
file_error_kind(enoent) -> file_not_found;
file_error_kind(eacces) -> access_denied;
file_error_kind({error, einval}) -> access_denied;
file_error_kind(efbig) -> file_size_limit_exceeded;
file_error_kind({error, Reason}) -> file_error_kind(Reason);
file_error_kind(_) -> unexpected.

contextual_file_error(Kind, Path, Reason) when is_binary(Path) ->
    contextual_error(Kind, {some, Path}, Reason);
contextual_file_error(Kind, Path, Reason) when is_list(Path) ->
    %% slate passes UTF-8 bytes to OTP via binary_to_list/1, not codepoints.
    contextual_error(Kind, {some, list_to_binary(Path)}, Reason);
contextual_file_error(Kind, undefined, Reason) ->
    contextual_error(Kind, none, Reason);
contextual_file_error(Kind, {From, To}, Reason) ->
    %% dets_utils:rename/2 reports both filenames. Neither alone identifies
    %% the failure, so retain the complete diagnostic rather than pick one.
    contextual_error(Kind, none, {file_error, {From, To}, Reason}).

contextual_error(Kind, Path, Reason) ->
    {Kind, {file_error_context, Path, format_reason(Reason)}}.

unexpected_error(Reason) ->
    {unexpected_error, format_reason(Reason)}.

format_reason(Reason) ->
    list_to_binary(io_lib:format("~p", [Reason])).
