-module(dotes_test_ffi).
-export([socket_lifecycle/2, socket_init_failure/0, runtime_file_responses/0]).

%% Real loopback sockets exercise Mist's on_close contract, not just Next values.
socket_lifecycle(Store, FailSend) ->
    {Client, Server} = socket_pair(),
    Parent = self(),
    Reference = make_ref(),
    OnInit = fun(Connection) ->
        {ok, {State = {socket, Component, _}, _} = Initialised} =
            dotes_web:init_socket(Store),
        {ok, ComponentPid} = 'gleam@erlang@process':subject_owner(Component),
        Parent ! {Reference, component, ComponentPid},
        case FailSend of
            true -> ok = gen_tcp:close(Server);
            false -> ok
        end,
        Initialised = dotes_web:finish_socket_init(Connection, {ok, Initialised}),
        Parent ! {Reference, state, State},
        Initialised
    end,
    OnClose = fun(State) ->
        dotes_web:close_socket(State),
        Parent ! {Reference, closed},
        nil
    end,
    Handler = fun(State, {user, Message}, Connection) ->
        dotes_web:loop_socket(State, {custom, Message}, Connection)
    end,
    try
        {ok, {started, WebsocketPid, _}} =
            'mist@internal@websocket':initialize_connection(
                OnInit, OnClose, Handler, Server, tcp, []
            ),
        ComponentPid = receive
            {Reference, component, Pid} -> Pid
        after 2000 -> error(component_not_started)
        end,
        SocketMonitor = monitor(process, WebsocketPid),
        ComponentMonitor = monitor(process, ComponentPid),
        receive {Reference, state, _} -> ok
        after 2000 -> error(socket_not_initialised)
        end,
        case FailSend of
            true -> ok;
            false ->
                ok = gen_tcp:controlling_process(Server, WebsocketPid),
                'mist@internal@websocket':set_active(tcp, Server),
                {ok, <<16#81, _/binary>>} = gen_tcp:recv(Client, 0, 2000),
                ok = gen_tcp:close(Client)
        end,
        receive {Reference, closed} -> ok
        after 2000 -> error(close_callback_not_called)
        end,
        await_down(SocketMonitor, WebsocketPid),
        await_down(ComponentMonitor, ComponentPid),
        false = is_process_alive(WebsocketPid),
        false = is_process_alive(ComponentPid),
        nil
    after
        gen_tcp:close(Client),
        gen_tcp:close(Server)
    end.

socket_init_failure() ->
    {Client, Server} = socket_pair(),
    PreviousTrap = process_flag(trap_exit, true),
    Parent = self(),
    Reference = make_ref(),
    OnInit = fun(Connection) ->
        Parent ! {Reference, initialising, self()},
        App = lustre:application(
            fun(_) ->
                Parent ! {Reference, component, self()},
                exit(normal)
            end,
            fun(Model, _) -> {Model, 'lustre@effect':none()} end,
            fun(_) -> 'lustre@element':none() end
        ),
        {error, _} = Started = lustre:start_server_component(App, nil),
        dotes_web:finish_socket_init(Connection, Started)
    end,
    try
        {error, _} = 'mist@internal@websocket':initialize_connection(
            OnInit, fun(_) -> error(unexpected_close_callback) end,
            fun(_, _, _) -> error(unexpected_message) end,
            Server, tcp, []
        ),
        WebsocketPid = receive {Reference, initialising, Pid} -> Pid
        after 2000 -> error(init_not_called)
        end,
        await_down(monitor(process, WebsocketPid), WebsocketPid),
        ComponentPid = receive {Reference, component, Child} -> Child
        after 2000 -> error(component_not_initialised)
        end,
        await_down(monitor(process, ComponentPid), ComponentPid),
        receive {'EXIT', WebsocketPid, _} -> ok after 0 -> ok end,
        {error, closed} = gen_tcp:recv(Client, 0, 2000),
        false = is_process_alive(WebsocketPid),
        nil
    after
        process_flag(trap_exit, PreviousTrap),
        gen_tcp:close(Client),
        gen_tcp:close(Server)
    end.

runtime_file_responses() ->
    {response, 200, _, _} = dotes_web:serve_runtime(),
    %% This VM is private to the tests; restore its code path even on failure.
    Path = filename:join(code:lib_dir(lustre), "ebin"),
    true = code:del_path(Path),
    try
        {response, 500, _, _} = dotes_web:serve_runtime(),
        nil
    after
        true = code:add_patha(Path)
    end.

socket_pair() ->
    {ok, Listener} = gen_tcp:listen(0, [binary, {active, false}, {ip, {127,0,0,1}}]),
    try
        {ok, {_, Port}} = inet:sockname(Listener),
        {ok, Client} = gen_tcp:connect({127,0,0,1}, Port, [binary, {active, false}]),
        {ok, Server} = gen_tcp:accept(Listener, 2000),
        {Client, Server}
    after
        gen_tcp:close(Listener)
    end.

await_down(Monitor, Pid) ->
    receive
        {'DOWN', Monitor, process, Pid, _} -> ok
    after 2000 -> error({process_still_running, Pid})
    end.
