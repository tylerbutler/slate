-module(exclusive_native_test_ffi).
-export([owner_death/0, unsafe_sidecars/0, unsupported_filesystem/0, os_failures/0]).

owner_death() ->
    {ok, nil} = slate_lock_nif:ensure_loaded(),
    Path = <<"test_exclusive_native_death.dets">>,
    Parent = self(),
    {Owner, Monitor} = spawn_monitor(fun() ->
        {ok, {Token, _}} = slate_lock_nif:acquire(Path),
        Parent ! {token, Token}
    end),
    Token = receive {token, T} -> T after 5000 -> error(native_acquire_timeout) end,
    receive {'DOWN', Monitor, process, Owner, normal} -> ok
    after 5000 -> error(native_owner_timeout) end,
    {error, busy} = slate_lock_nif:acquire(Path),
    {ok, nil} = slate_lock_nif:release(Token),
    {error, {os_failure, _}} = slate_lock_nif:release(Token),
    {ok, {Next, _}} = slate_lock_nif:acquire(Path),
    {ok, nil} = slate_lock_nif:release(Next),
    exclusive_test_ffi:cleanup_sidecar(Path).

unsafe_sidecars() ->
    {ok, nil} = slate_lock_nif:ensure_loaded(),
    Path = <<"test_exclusive_native_sidecar.dets">>,
    Sidecar = "test_exclusive_native_sidecar.dets.slate.lock",
    Target = "test_exclusive_native_sidecar.target",
    ok = file:write_file(Target, <<>>),
    try
        ok = file:make_symlink(filename:absname(Target), Sidecar),
        try
            {error, {unsafe_alias, _}} = slate_lock_nif:acquire(Path)
        after ok = file:delete(Sidecar) end,
        ok = file:make_link(Target, Sidecar),
        try
            {error, {unsafe_alias, _}} = slate_lock_nif:acquire(Path)
        after ok = file:delete(Sidecar) end,
        ok = file:make_dir(Sidecar),
        try
            {error, {unsafe_alias, _}} = slate_lock_nif:acquire(Path)
        after ok = file:del_dir(Sidecar) end
    after ok = file:delete(Target) end,
    nil.

unsupported_filesystem() ->
    case os:type() of
        {unix, linux} ->
            {ok, nil} = slate_lock_nif:ensure_loaded(),
            {error, {unsupported_filesystem, _}} =
                slate_lock_nif:acquire(<<"/proc/version">>);
        _ -> ok
    end,
    nil.

os_failures() ->
    {ok, nil} = slate_lock_nif:ensure_loaded(),
    {error, {os_failure, _}} = slate_lock_nif:acquire(
        <<"test_exclusive_missing_parent/data.dets">>),
    Path = <<"test_exclusive_permissions.dets">>,
    Sidecar = "test_exclusive_permissions.dets.slate.lock",
    ok = file:write_file(Sidecar, <<>>),
    try
        ok = file:change_mode(Sidecar, 8#400),
        {error, {os_failure, _}} = slate_lock_nif:acquire(Path)
    after
        ok = file:change_mode(Sidecar, 8#600),
        ok = file:delete(Sidecar)
    end,
    nil.
