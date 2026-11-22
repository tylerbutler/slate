-module(slate_loader_probe).
-export([main/1]).

%% Each archive runs in a fresh VM without a slate application on its code path.
main([Mode, ExpectedScript, ChangedCwd]) ->
    ExpectedScript = escript:script_name(),
    {error, bad_name} = code:priv_dir(slate),
    {module, slate_lock_nif} = code:ensure_loaded(slate_lock_nif),
    %% Loading the BEAM itself must not load native code, even with a companion.
    try slate_lock_nif:acquire(<<"unused">>) of
        Value -> error({native_loaded_eagerly, Value})
    catch
        error:native_not_loaded -> ok
    end,
    ok = file:set_cwd(ChangedCwd),
    Result = slate_lock_nif:ensure_loaded(),
    case Mode of
        "reject" ->
            Detail = unicode:characters_to_binary(io_lib:format(
                "~tp", [{escript_path_not_absolute, ExpectedScript}])),
            {error, {native_unavailable, Detail}} = Result,
            %% A failed lazy attempt must not change the result on retry.
            Result = slate_lock_nif:ensure_loaded();
        "loaded" ->
            absolute = filename:pathtype(ExpectedScript),
            {ok, nil} = Result,
            {ok, nil} = slate_lock_nif:ensure_loaded();
        "missing" ->
            absolute = filename:pathtype(ExpectedScript),
            {error, {native_unavailable, Detail}} = Result,
            true = is_binary(Detail),
            true = byte_size(Detail) > 0
    end,
    io:format("Loader probe ~s passed (~ts).~n", [Mode, ExpectedScript]).
