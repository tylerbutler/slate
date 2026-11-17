-module(coordination_test_ffi).
-export([run/0, failure/0, failure_fixture/0, run_failure/0]).

%% Gleam interface: @external(erlang, "coordination_test_ffi", "run")
%% fn run() -> Nil
%% Assertions raise on failure. Sequential, no files or production test hooks.
run() ->
    concurrent_start(),
    caller_and_exceptions(),
    fifo_and_waiter_death(),
    holder_death(),
    drained(),
    nil.

concurrent_start() ->
    Parent = self(),
    Workers = [spawn_monitor(fun() ->
        receive go -> ok end,
        ok = slate_dets_coordination:with({make_ref(), I}, fun() -> ok end),
        Parent ! {started, self()}
    end) || I <- lists:seq(1, 24)],
    try
        [Pid ! go || {Pid, _} <- Workers],
        [receive {started, Pid} -> ok
         after 5000 -> error({startup_timeout, Pid})
         end || {Pid, _} <- Workers],
        Server = whereis(slate_dets_coordination),
        true = is_pid(Server),
        Server = persistent_term:get(slate_dets_coordination),
        {slate_dets_coordination, Server, worker, _} =
            lists:keyfind(slate_dets_coordination, 1,
                          supervisor:which_children(kernel_safe_sup))
    after
        [cleanup(Pid, Ref) || {Pid, Ref} <- Workers]
    end,
    drained().

caller_and_exceptions() ->
    Resource = {generic, make_ref(), #{not_just_table_names => true}},
    Caller = self(),
    Caller = slate_dets_coordination:with(Resource, fun() -> self() end),
    lists:foreach(fun(Class) ->
        try slate_dets_coordination:with(Resource, fun() ->
            erlang:raise(Class, expected, [])
        end) of
            _ -> error({exception_swallowed, Class})
        catch
            Class:expected -> ok
        end,
        %% Same caller's release precedes this new acquisition.
        released = slate_dets_coordination:with(Resource, fun() -> released end)
    end, [throw, error, exit]),
    drained().

fifo_and_waiter_death() ->
    Resource = {fifo, make_ref()},
    with_worker(Resource, fun(Holder) ->
        entered(Holder),
        with_worker(Resource, fun(First) ->
            table_name_race_test_ffi:await_coordination(First),
            with_worker(Resource, fun(Dead) ->
                table_name_race_test_ffi:await_coordination(Dead),
                with_worker(Resource, fun(Last) ->
                    table_name_race_test_ffi:await_coordination(Last),
                    assert_waiters(Resource, [First, Dead, Last]),
                    exit(Dead, kill),
                    await(fun() -> waiter_pids(Resource) =:= [First, Last] end),
                    %% A blocked resource must not block unrelated work.
                    independent = slate_dets_coordination:with(
                        {independent, make_ref()}, fun() -> independent end),
                    Holder ! release,
                    finished(Holder),
                    entered(First),
                    assert_waiters(Resource, [Last]),
                    First ! release,
                    finished(First),
                    entered(Last),
                    Last ! release,
                    finished(Last)
                end)
            end)
        end)
    end),
    drained().

holder_death() ->
    Resource = {holder_death, make_ref()},
    with_worker(Resource, fun(Holder) ->
        entered(Holder),
        with_worker(Resource, fun(Next) ->
            table_name_race_test_ffi:await_coordination(Next),
            exit(Holder, kill),
            entered(Next),
            Next ! release,
            finished(Next)
        end)
    end),
    drained().

with_worker(Resource, Test) ->
    Parent = self(),
    {Pid, Ref} = spawn_monitor(fun() ->
        slate_dets_coordination:with(Resource, fun() ->
            Parent ! {entered, self()},
            receive release -> ok end
        end),
        Parent ! {finished, self()}
    end),
    try Test(Pid)
    after cleanup(Pid, Ref)
    end.

cleanup(Pid, Ref) ->
    exit(Pid, kill),
    receive {'DOWN', Ref, process, Pid, _} -> ok
    after 5000 -> error({cleanup_timeout, Pid})
    end.

entered(Pid) ->
    %% Match any admission, so out-of-order grants fail rather than being
    %% skipped by selective receive until the expected worker is granted.
    receive {entered, Actual} when Actual =:= Pid -> ok;
            {entered, Other} -> error({out_of_order, Pid, Other})
    after 5000 -> error({admission_timeout, Pid})
    end.

finished(Pid) ->
    receive {finished, Pid} -> ok
    after 5000 -> error({release_timeout, Pid})
    end.

assert_waiters(Resource, Expected) ->
    Expected = waiter_pids(Resource).

waiter_pids(Resource) ->
    #{resources := Resources, requests := Requests} =
        sys:get_state(slate_dets_coordination),
    case maps:find(Resource, Resources) of
        error -> [];
        {ok, #{waiters := Waiters}} ->
            [Pid || Token <- queue:to_list(Waiters),
                    {_, {Pid, _}} <- [maps:get(Token, Requests)]]
    end.

drained() ->
    await(fun() ->
        sys:get_state(slate_dets_coordination) =:=
            #{resources => #{}, requests => #{}}
    end),
    {monitors, []} = process_info(whereis(slate_dets_coordination), monitors),
    ok.

await(Check) ->
    await(Check, erlang:monotonic_time(millisecond) + 5000).

await(Check, Deadline) ->
    case Check() of
        true -> ok;
        false ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> timer:sleep(1), await(Check, Deadline);
                false -> error(coordination_assertion_timeout)
            end
    end.

%% Safe in the main suite: the irreversible failure runs in another OS VM.
%% Gleam interface: @external(erlang, "coordination_test_ffi", "failure")
%% fn failure() -> Nil
failure() ->
    exclusive_vm_test_ffi:with_poisoned_path(fun() ->
        Args = ["+S", "2", "+A", "1", "-noshell", "-pa"] ++ code:get_path() ++
            ["-eval", "coordination_test_ffi:failure_fixture(), halt()."],
        Port = open_port({spawn_executable, exclusive_vm_test_ffi:erl_executable()},
                         [binary, exit_status, stderr_to_stdout, {args, Args}]),
        try await_vm(Port, <<>>, erlang:monotonic_time(millisecond) + 20000)
        after
            try port_close(Port) catch error:badarg -> ok end
        end
    end).

await_vm(Port, Output, Deadline) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Data}} ->
            await_vm(Port, <<Output/binary, Data/binary>>, Deadline);
        {Port, {exit_status, 0}} ->
            true = binary:match(Output, <<"coordination_fail_closed_ok">>) =/= nomatch,
            nil;
        {Port, {exit_status, Code}} ->
            error({coordination_fixture_failed, Code, Output})
    after Remaining -> error({coordination_fixture_timeout, Output})
    end.

failure_fixture() ->
    %% Bound the child even if a test assertion/cleanup unexpectedly blocks.
    spawn(fun() -> timer:sleep(15000), erlang:halt(99) end),
    nil = run_failure(),
    io:format("coordination_fail_closed_ok~n").

%% DESTRUCTIVE: run ONLY in a disposable, otherwise unused VM. Never call
%% from the normal Gleam suite: the fixed marker intentionally cannot reset.
%% Gleam interface, if invoked in a separate VM: fn run_failure() -> Nil
run_failure() ->
    run(),
    Path = list_to_binary("test_coordination_failure_" ++ os:getpid() ++ ".dets"),
    {ok, Table} = slate_dets_ffi:open_set(Path, no_repair),
    try
        {ok, nil} = slate_dets_ffi:insert(Table, {base, 7}),
        run_failure(Table, Path)
    after
        %% Only this disposable fixture bypasses failed admission for cleanup.
        _ = dets:close(Table),
        _ = file:delete(Path)
    end,
    nil.

run_failure(Table, Path) ->
    Resource = {mutation, slate_dets_ffi:table_name(Table)},
    with_worker(Resource, fun(Holder) ->
        entered(Holder),
        Parent = self(),
        {Waiter, Ref} = spawn_monitor(fun() ->
            try slate_dets_coordination:with(Resource, fun() ->
                error(waiter_must_not_run)
            end) of
                _ -> error(waiter_must_not_succeed)
            catch
                error:{slate_dets_coordination_unavailable, _} ->
                    Parent ! {failed_closed, self()}
            end
        end),
        Queued = [spawn_monitor(fun() ->
            assert_public_failure(Kind, Call()),
            Parent ! {public_failed_closed, self()}
        end) || {Kind, Call} <- [
            {ordinary, fun() -> slate_dets_ffi:insert(Table, {base, 99}) end},
            {counter, fun() -> slate_dets_ffi:update_counter(Table, base, 1) end},
            {ordinary, fun() -> slate_dets_ffi:close(Table) end}
        ]],
        try
            table_name_race_test_ffi:await_coordination(Waiter),
            [table_name_race_test_ffi:await_coordination(Pid) || {Pid, _} <- Queued],
            Server = whereis(slate_dets_coordination),
            ServerRef = monitor(process, Server),
            exit(Server, kill),
            receive {'DOWN', ServerRef, process, Server, killed} -> ok
            after 5000 -> error(server_did_not_stop)
            end,
            receive {failed_closed, Waiter} -> ok
            after 5000 -> error(waiter_did_not_fail)
            end,
            [receive {public_failed_closed, Pid} -> ok
             after 5000 -> error({queued_public_call_did_not_fail, Pid})
             end || {Pid, _} <- Queued],
            public_failure_shapes(Table, Path),
            true = is_process_alive(Holder),
            await(fun() ->
                not lists:keymember(slate_dets_coordination, 1,
                    supervisor:which_children(kernel_safe_sup))
            end),
            %% A stale start_child that read undefined before the first start
            %% must also be rejected, not just ordinary marker-aware clients.
            Child = #{id => slate_dets_coordination,
                      start => {slate_dets_coordination, start_link, []},
                      restart => temporary},
            {error, {{slate_dets_coordination_already_started, Server}, _}} =
                supervisor:start_child(kernel_safe_sup, Child),
            Server = persistent_term:get(slate_dets_coordination),
            undefined = whereis(slate_dets_coordination),
            try slate_dets_coordination:with(Resource, fun() ->
                error(replacement_must_not_run)
            end) of
                _ -> error(replacement_must_not_succeed)
            catch
                error:{slate_dets_coordination_unavailable, _} -> ok
            end,
            %% The old holder can finish, including its after release.
            Holder ! release,
            finished(Holder)
        after
            cleanup(Waiter, Ref),
            [cleanup(Pid, Monitor) || {Pid, Monitor} <- Queued]
        end
    end),
    nil.

public_failure_shapes(Table, Path) ->
    %% Exercise both ordinary and exclusive-reference normalization/translation.
    lists:foreach(fun(Name) ->
        [assert_public_failure(ordinary, Result) || Result <- [
            slate_dets_ffi:insert(Name, {base, 99}),
            slate_dets_ffi:insert_new(Name, {new_key, 99}),
            slate_dets_ffi:insert_new_object(Name, {new_key, 99}),
            slate_dets_ffi:delete_key(Name, base),
            slate_dets_ffi:delete_object(Name, {base, 7}),
            slate_dets_ffi:delete_all(Name),
            slate_dets_ffi:close(Name)
        ]],
        assert_public_failure(counter, slate_dets_ffi:update_counter(Name, base, 1))
    end, [Table, {slate_exclusive, Table}]),
    assert_public_failure(ordinary, slate_dets_ffi:open_set(Path, no_repair)),
    OtherPath = <<Path/binary, ".unopened">>,
    assert_public_failure(ordinary, slate_dets_ffi:open_set(OtherPath, no_repair)),
    false = filelib:is_file(OtherPath),
    %% Failed admission must neither mutate the file nor close its table.
    [{base, 7}] = dets:lookup(Table, base),
    [] = dets:lookup(Table, new_key),
    1 = dets:info(Table, size),
    ok.

assert_public_failure(counter, {error, {ffi_table_error, Translated}}) ->
    assert_public_failure(ordinary, {error, Translated});
assert_public_failure(ordinary, {error, {unexpected_error, Detail}})
  when is_binary(Detail) ->
    true = binary:match(Detail, <<"slate_dets_coordination_unavailable">>) =/= nomatch,
    ok.
