-module(entrypoint_test_ffi).
-export([exercise/2, run/2, port/2, start_web/1, start_tui/1, columns/0, rows/0]).

%% Disposable-VM tests of the real public main functions. Only directory/port
%% selection and terminal IO are redirected; no UI logic or Store is forged.
exercise(Mode, Directory) ->
    ok = application:set_env(dotes_entrypoint_test, directory, Directory),
    ok = application:set_env(dotes_entrypoint_test, mode, Mode),
    {ok, Listener} = gen_tcp:listen(0, [{ip, {127,0,0,1}}, {active, false}]),
    {ok, {_, Port}} = inet:sockname(Listener),
    ok = application:set_env(dotes_entrypoint_test, port,
                            case Mode of web_busy -> Port; _ -> 0 end),
    try
        lists:foreach(fun patch/1, ['dotes@web', 'dotes@tui', 'shore@internal']),
        lists:foreach(fun(Trap) -> exercise_main(Mode, Directory, Trap) end,
                      [false, true]),
        nil
    after
        gen_tcp:close(Listener)
    end.

patch(Module) ->
    {module, Module} = code:ensure_loaded(Module),
    Beam = code:which(Module),
    {ok, {Module, [{abstract_code, {raw_abstract_v1, Forms}}]}} =
        beam_lib:chunks(Beam, [abstract_code]),
    {ok, Module, Binary} = compile:forms(rewrite(Forms), [binary]),
    {module, Module} = code:load_binary(Module, Beam, Binary).

rewrite({remote, L, {atom, ML, Module}, {atom, FL, Function}} = Original) ->
    Replacement = case {Module, Function} of
        {'dotes@lifecycle', run} -> run;
        {mist, port} -> port;
        {mist, start} -> start_web;
        {shore, start} -> start_tui;
        {io, columns} -> columns;
        {io, rows} -> rows;
        _ -> none
    end,
    case Replacement of
        none -> Original;
        _ -> {remote, L, {atom, ML, ?MODULE}, {atom, FL, Replacement}}
    end;
rewrite(Tuple) when is_tuple(Tuple) ->
    list_to_tuple([rewrite(Element) || Element <- tuple_to_list(Tuple)]);
rewrite(List) when is_list(List) -> [rewrite(Element) || Element <- List];
rewrite(Value) -> Value.

run(_DefaultDirectory, Start) ->
    {ok, Directory} = application:get_env(dotes_entrypoint_test, directory),
    'dotes@lifecycle':run(Directory, Start).

port(Builder, _DefaultPort) ->
    {ok, Port} = application:get_env(dotes_entrypoint_test, port),
    mist:port(Builder, Port).

start_web(Builder) ->
    Result = mist:start(Builder),
    case Result of
        {ok, {started, Pid, _}} -> started(Pid);
        {error, _} -> ok
    end,
    Result.

start_tui(Spec) ->
    Result = case application:get_env(dotes_entrypoint_test, mode) of
        {ok, tui_startup_exit} -> shore:start(Spec);
        {ok, tui_runtime_exit} ->
            %% Real Shore actor and redraw timer, with no OTP-28 raw terminal
            %% IO requirement. All rendering messages stay in the private
            %% lifecycle worker, which owns this real Subject.
            Renderer = 'gleam@erlang@process':new_subject(),
            'shore@internal':start_custom_renderer(Spec, {some, Renderer})
    end,
    case Result of
        {ok, Subject} ->
            {ok, Pid} = 'gleam@erlang@process':subject_owner(Subject),
            started(Pid);
        {error, _} -> ok
    end,
    Result.

columns() ->
    case application:get_env(dotes_entrypoint_test, mode) of
        {ok, tui_startup_exit} -> {error, enotsup};
        _ -> {ok, 80}
    end.

rows() -> {ok, 24}.

started(Pid) ->
    whereis(dotes_store_test_controller) ! {runtime_started, self(), Pid},
    ok.

exercise_main(Mode, Directory, Trap) ->
    Controller = self(),
    Reference = make_ref(),
    Caller = spawn(fun() ->
        process_flag(trap_exit, Trap),
        %% Preserve unrelated caller messages, including a genuine linked EXIT
        %% when the caller already traps. The helper must not reset its flag.
        Sentinel = spawn_link(fun() -> ok end),
        await_down(monitor(process, Sentinel), Sentinel),
        self() ! {unrelated, Reference},
        {messages, Before} = process_info(self(), messages),
        Output = store_test_ffi:capture_output(fun() ->
            case Mode of
                web_busy -> 'dotes@web':main();
                web_runtime_exit -> 'dotes@web':main();
                tui_startup_exit -> 'dotes@tui':main();
                tui_runtime_exit -> 'dotes@tui':main()
            end
        end),
        {trap_exit, Trap} = process_info(self(), trap_exit),
        {messages, Before} = process_info(self(), messages),
        %% Immediate, no retry: explicit cleanup must precede main's return.
        {ok, Store} = 'dotes@store':open_in(Directory),
        {ok, nil} = 'dotes@store':close(Store),
        Controller ! {Reference, completed, Output}
    end),
    Monitor = monitor(process, Caller),
    Linked = case Mode of
        web_runtime_exit -> kill_running_child();
        tui_runtime_exit -> kill_running_child();
        _ -> []
    end,
    Output = receive
        {Reference, completed, Captured} -> Captured;
        {'DOWN', Monitor, process, Caller, Reason} ->
            error({entrypoint_did_not_return, Mode, Trap, Reason})
    after 10000 -> error({entrypoint_timeout, Mode, Trap})
    end,
    await_down(Monitor, Caller),
    lists:foreach(fun(Pid) -> await_down(monitor(process, Pid), Pid) end, Linked),
    Expected = case Mode of
        web_busy -> <<"Cannot start the dotes web server">>;
        tui_startup_exit -> <<"Cannot start the dotes terminal">>;
        _ -> <<"The dotes application stopped unexpectedly.">>
    end,
    true = binary:match(Output, Expected) =/= nomatch,
    false = binary:match(Output, <<"Error closing store:">>) =/= nomatch,
    ok.

kill_running_child() ->
    receive
        {runtime_started, Worker, Child} ->
            await_monitor(Worker, Child, erlang:monotonic_time(millisecond) + 5000),
            {links, Linked} = process_info(Worker, links),
            exit(Child, kill),
            [Worker | Linked]
    after 5000 -> error(runtime_not_started)
    end.

await_monitor(Worker, Child, Deadline) ->
    {monitors, Monitors} = process_info(Worker, monitors),
    case lists:member({process, Child}, Monitors) of
        true -> ok;
        false ->
            case erlang:monotonic_time(millisecond) >= Deadline of
                true -> error(runtime_monitor_not_established);
                false -> receive after 1 -> await_monitor(Worker, Child, Deadline) end
            end
    end.

await_down(Monitor, Pid) ->
    receive {'DOWN', Monitor, process, Pid, _} -> ok
    after 5000 -> error({process_did_not_stop, Pid})
    end.
