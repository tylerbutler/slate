-module(path_test_ffi).
-export([delete_file/1, is_absolute/1, canonical_path/1,
         above_root_alias/1, root_cases/0, same_table/2]).

is_absolute(Path) ->
    filename:pathtype(binary_to_list(Path)) =:= absolute.

canonical_path(Path) ->
    list_to_binary(slate_dets_ffi:canonicalize_path(Path)).

above_root_alias(Path) ->
    Parts = filename:split(binary_to_list(Path)),
    {Anchor, Rest} = case Parts of
        ["//", Server, Share | Tail] -> {["//", Server, Share], Tail};
        [Root | Tail] -> {[Root], Tail}
    end,
    list_to_binary(filename:join(Anchor ++ ["..", "..", "."] ++ Rest)).

root_cases() ->
    case os:type() of
        {unix, _} ->
            [{<<"/../absolute/path">>, <<"/absolute/path">>},
             {<<"/../.././absolute/../path">>, <<"/path">>},
             {<<"/../../..">>, <<"/">>}];
        {win32, _} ->
            [{<<"C:/../absolute/path">>, <<"c:/absolute/path">>},
             {<<"C:/../.././absolute/../path">>, <<"c:/path">>},
             {<<"C:/../../..">>, <<"c:/">>},
             {<<"//server/share/../../absolute/../path">>, <<"//server/share/path">>},
             {<<"//server/share/../../..">>, <<"//server/share">>}]
    end.

same_table({Type, First, _, _}, {Type, Second, _, _}) ->
    FirstPid = slate_exclusive_table_ffi:table_pid(First),
    FirstPid =:= slate_exclusive_table_ffi:table_pid(Second).

delete_file(Path) ->
    case file:delete(binary_to_list(Path)) of
        ok -> {ok, nil};
        {error, Reason} -> {error, Reason}
    end.
