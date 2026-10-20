-module(close_lifetime_test_ffi).
-export([with_collision_paths/1, with_suspended_table/2, resume/1,
         await_unregistered/1, await_queued_open/2, different_names/2,
         await_released/1, with_suspended_path/2, reserved/1,
         registry_failure/0, registry_failure_fixture/0, track_worker/1,
         await_old_server_monitor/2, with_delayed_owner_exit/2,
         await_queued_fence/2, track_table/1, await_fence_completion/1,
         registry_tracks/1]).

with_collision_paths(Callback) ->
    Prefix = "test_close_lifetime_" ++
        integer_to_list(erlang:unique_integer([positive, monotonic])) ++ "_",
    {First, Second} = collision(Prefix, 0, #{}),
    Previous = put(?MODULE, []),
    PreviousTables = put({?MODULE, tables}, []),
    try Callback(First, Second)
    after
        %% Stop/join fixture workers before deleting either file, including on
        %% assertion failure. The suspension scope has already resumed DETS.
        Workers = get(?MODULE),
        Tables = get({?MODULE, tables}),
        case Previous of undefined -> erase(?MODULE); _ -> put(?MODULE, Previous) end,
        case PreviousTables of
            undefined -> erase({?MODULE, tables});
            _ -> put({?MODULE, tables}, PreviousTables)
        end,
        lists:foreach(fun(Pid) ->
            Ref = monitor(process, Pid),
            exit(Pid, kill),
            receive {'DOWN', Ref, process, Pid, _} -> ok end
        end, Workers),
        cleanup_table(First),
        cleanup_table(Second),
        %% A failing stale-fence regression may have lost the reservation.
        %% Still join every captured DETS PID before deleting its actual file.
        lists:foreach(fun await_table_down/1, Tables),
        _ = file:delete(First),
        _ = file:delete(Second)
    end.

cleanup_table(Path) ->
    case slate_dets_lifetime:find(slate_dets_ffi:canonicalize_path(Path)) of
        {ok, Name} -> _ = dets:close(Name);
        error -> ok
    end,
    await_released(Path).

track_table(Table) ->
    Pid = table_name_race_test_ffi:table_pid(Table),
    true = is_pid(Pid),
    Tables = get({?MODULE, tables}),
    true = is_list(Tables),
    put({?MODULE, tables}, [Pid | Tables]),
    Pid.

await_table_down(Pid) ->
    Ref = monitor(process, Pid),
    try
        receive {'DOWN', Ref, process, Pid, _} -> ok
        after 5000 -> error({fixture_table_still_alive, Pid})
        end
    after demonitor(Ref, [flush])
    end.

await_fence_completion(Path) ->
    Canonical = slate_dets_ffi:canonicalize_path(Path),
    await(fun() ->
        {state, _Paths, _Names, Openings, _Monitors} = sys:get_state(slate_dets_lifetime),
        not lists:any(fun
            ({opening, OpenPath, _, _, _, _}) -> OpenPath =:= Canonical
        end, maps:values(Openings))
    end).

registry_tracks(Table) ->
    Pid = table_name_race_test_ffi:table_pid(Table),
    {monitors, Monitors} = process_info(whereis(slate_dets_lifetime), monitors),
    lists:member({process, Pid}, Monitors).

track_worker(Pid) ->
    Workers = get(?MODULE),
    true = is_list(Workers),
    put(?MODULE, [Pid | Workers]),
    nil.

collision(Prefix, Number, Seen) ->
    Path = list_to_binary(Prefix ++ integer_to_list(Number) ++ ".dets"),
    Slot = erlang:phash2(slate_dets_ffi:canonicalize_path(Path), 4096),
    case maps:find(Slot, Seen) of
        {ok, Previous} -> {Previous, Path};
        error -> collision(Prefix, Number + 1, Seen#{Slot => Path})
    end.

with_suspended_table({_Type, Reference, _, _}, Callback) ->
    Name = slate_dets_ffi:table_name(Reference),
    with_suspended_name(Name, Callback).

with_suspended_path(Path, Callback) ->
    {ok, Name} = slate_dets_lifetime:find(slate_dets_ffi:canonicalize_path(Path)),
    with_suspended_name(Name, Callback).

with_suspended_name(Name, Callback) ->
    Pid = dets:info(Name, owner),
    true = erlang:suspend_process(Pid),
    try Callback({suspended_table, Name, Pid})
    after
        %% A successful callback resumes explicitly and waits for DOWN. Also
        %% release the server on assertion failures, never strand a DETS file.
        try erlang:resume_process(Pid)
        catch error:badarg -> ok
        end
    end.

resume({suspended_table, _Name, Pid}) ->
    true = erlang:resume_process(Pid),
    nil.

await_unregistered({suspended_table, Name, Pid}) ->
    await(fun() ->
        is_process_alive(Pid) andalso dets:info(Name, owner) =:= undefined
    end).

await_queued_open({suspended_table, Name, OldPid}, Opener) ->
    %% Test-only inspection of OTP 27's pending record: prove the new request
    %% is behind the old close for the SAME name, not merely unscheduled.
    await(fun() ->
        {state, _Store, _Parent, Pending} = sys:get_state(dets),
        lists:any(fun
            ({pending, Tab, _, Pid, _, internal_close, Clients})
              when Tab =:= Name, Pid =:= OldPid ->
                lists:any(fun
                    ({{open, Requested, _}, {From, _}}) ->
                        Requested =:= Name andalso From =:= Opener;
                    (_) -> false
                end, Clients);
            (_) -> false
        end, Pending)
    end).

await_queued_fence({suspended_table, Name, OldPid}, Worker) ->
    await(fun() ->
        {state, _Store, _Parent, Pending} = sys:get_state(dets),
        lists:any(fun
            ({pending, Tab, _, Pid, _, internal_close, Clients})
              when Tab =:= Name, Pid =:= OldPid ->
                lists:any(fun
                    ({{close, Requested}, {From, _}}) ->
                        Requested =:= Name andalso From =:= Worker;
                    (_) -> false
                end, Clients);
            (_) -> false
        end, Pending)
    end).

with_delayed_owner_exit(Owner, Callback) ->
    %% Delay the REAL exit notification, not a fabricated DETS result. There
    %% is no cross-recipient ordering guarantee between this EXIT and the
    %% lifetime registry's DOWN. Force the registry's fence to arrive first.
    Dets = whereis(dets),
    Parent = self(),
    Ref = make_ref(),
    Release = fun() ->
        receive {Ref, Exit} -> Dets ! Exit
        after 0 -> ok
        end,
        nil
    end,
    ok = sys:suspend(Dets),
    try
        exit(Owner, kill),
        _ = sys:replace_state(Dets, fun(State) ->
            receive
                {'EXIT', Owner, _} = Exit -> Parent ! {Ref, Exit}
            after 5000 -> error(owner_exit_not_received)
            end,
            State
        end, 10000),
        ok = sys:resume(Dets),
        Callback(Release)
    after
        Release(),
        ok = sys:resume(Dets)
    end.

await_old_server_monitor({suspended_table, _Name, OldPid}, Opener) ->
    await(fun() ->
        case process_info(Opener, monitors) of
            {monitors, Monitors} -> lists:member({process, OldPid}, Monitors);
            undefined -> false
        end
    end).

different_names({_Type, First, _, _}, {_OtherType, Second, _, _}) ->
    slate_dets_ffi:table_name(First) =/= slate_dets_ffi:table_name(Second).

await_released(Path) ->
    Canonical = slate_dets_ffi:canonicalize_path(Path),
    await(fun() -> slate_dets_lifetime:find(Canonical) =:= error end).

reserved(Path) ->
    slate_dets_lifetime:find(slate_dets_ffi:canonicalize_path(Path)) =/= error.

registry_failure() ->
    %% Exercise this launch with a broken erl first on PATH, just like the
    %% existing exclusive VM fixture. Its scope always restores the environment.
    exclusive_vm_test_ffi:with_poisoned_path(fun() ->
        Args = ["+S", "2", "+A", "1", "-noshell", "-pa"] ++ code:get_path() ++
            ["-eval", "close_lifetime_test_ffi:registry_failure_fixture(), halt()."],
        Port = open_port({spawn_executable, exclusive_vm_test_ffi:erl_executable()},
                         [binary, exit_status, stderr_to_stdout, {args, Args}]),
        try await_vm(Port, <<>>)
        after
            try port_close(Port) catch error:badarg -> ok end
        end
    end).

await_vm(Port, Output) ->
    receive
        {Port, {data, Data}} -> await_vm(Port, <<Output/binary, Data/binary>>);
        {Port, {exit_status, 0}} ->
            true = binary:match(Output, <<"registry_fail_closed_ok">>) =/= nomatch,
            nil;
        {Port, {exit_status, Code}} -> error({registry_fixture_failed, Code, Output})
    after 15000 -> error(registry_fixture_timeout)
    end.

registry_failure_fixture() ->
    %% Bound even an unexpectedly stuck child; never poison the root test VM.
    spawn(fun() -> timer:sleep(10000), erlang:halt(99) end),
    Path = list_to_binary("test_registry_failure_" ++ os:getpid() ++ ".dets"),
    try
        {ok, Table} = slate_dets_ffi:open_set(Path, no_repair),
        {ok, nil} = slate_dets_ffi:insert(Table, {base, 1}),
        Registry = whereis(slate_dets_lifetime),
        Monitor = monitor(process, Registry),
        exit(Registry, kill),
        receive {'DOWN', Monitor, process, Registry, killed} -> ok end,
        {error, {unexpected_error, _}} = slate_dets_ffi:open_set(Path, no_repair),
        {error, {unexpected_error, _}} =
            slate_dets_ffi:open_set(<<"test_registry_must_not_create.dets">>, no_repair),
        false = filelib:is_file("test_registry_must_not_create.dets"),
        {ok, 1} = slate_dets_ffi:lookup(Table, base),
        {ok, nil} = slate_dets_ffi:close(Table),
        undefined = whereis(slate_dets_lifetime),
        io:format("registry_fail_closed_ok~n")
    after
        _ = file:delete(Path)
    end.

await(Check) ->
    await(Check, erlang:monotonic_time(millisecond) + 5000).

await(Check, Deadline) ->
    case Check() of
        true -> nil;
        false ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> timer:sleep(1), await(Check, Deadline);
                false -> error(lifetime_condition_timeout)
            end
    end.
