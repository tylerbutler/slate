-module(unicode_cwd_test_ffi).
-export([in_directory/2, delete_file/1]).

%% Tests run sequentially: cwd belongs to the VM, not the calling process.
in_directory(Directory, Callback) ->
    {ok, Original} = file:get_cwd(),
    Unique = "test_unicode_cwd_" ++ integer_to_list(erlang:unique_integer([positive])),
    Root = filename:join(Original, Unique),
    Path = filename:join(Root, unicode:characters_to_list(Directory)),
    ok = file:make_dir(Root),
    try
        ok = file:make_dir(Path),
        try
            ok = file:set_cwd(Path),
            {ok, Actual} = file:get_cwd(),
            Callback(unicode:characters_to_binary(Actual))
        after
            ok = file:set_cwd(Original),
            ok = file:del_dir_r(Path)
        end
    after
        ok = file:del_dir(Root)
    end.

delete_file(Path) ->
    case file:delete(Path) of
        ok -> {ok, nil};
        {error, Reason} -> {error, Reason}
    end.
