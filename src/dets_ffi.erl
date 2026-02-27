-module(dets_ffi).
-export([
    open_set/2, open_bag/2, open_duplicate_bag/2,
    close/1, insert/2, insert_new/2,
    lookup/2, lookup_all/2, delete_key/2, delete_all/1,
    member/2, sync/1, fold/3, to_list/1,
    info_size/1, info_file_size/1
]).

%% ── Open ────────────────────────────────────────────────────────────────

open_set(Path, Repair) ->
    do_open(Path, set, Repair).

open_bag(Path, Repair) ->
    do_open(Path, bag, Repair).

open_duplicate_bag(Path, Repair) ->
    do_open(Path, duplicate_bag, Repair).

do_open(Path, Type, Repair) ->
    Name = binary_to_atom(Path, utf8),
    RepairVal = repair_value(Repair),
    Opts = [{file, binary_to_list(Path)}, {type, Type}, {repair, RepairVal}],
    try dets:open_file(Name, Opts) of
        {ok, Name} -> {ok, Name};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% Gleam RepairPolicy constructors map to these atoms:
%%   auto_repair -> true, force_repair -> force, no_repair -> false
repair_value(auto_repair) -> true;
repair_value(force_repair) -> force;
repair_value(no_repair) -> false.

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
    try dets:foldl(Fun, Acc0, Name) of
        Result -> {ok, Result}
    catch
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
    case dets:info(Name, size) of
        undefined -> {error, {erlang_error, <<"Table does not exist">>}};
        N -> {ok, N}
    end.

info_file_size(Name) ->
    case dets:info(Name, file_size) of
        undefined -> {error, {erlang_error, <<"Table does not exist">>}};
        N -> {ok, N}
    end.

%% ── Error translation ──────────────────────────────────────────────────
%% Maps Erlang DETS errors to atoms matching Gleam DetsError constructors.

translate_error(not_found) -> not_found;
translate_error(key_already_present) -> key_already_present;
translate_error({file_error, _, enoent}) -> file_not_found;
translate_error({file_error, _, eacces}) -> file_not_found;
translate_error(badarg) -> table_does_not_exist;
translate_error({error, Reason}) -> translate_error(Reason);
translate_error(Reason) ->
    {erlang_error, list_to_binary(io_lib:format("~p", [Reason]))}.
