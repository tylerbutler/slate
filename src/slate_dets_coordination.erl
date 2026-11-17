-module(slate_dets_coordination).
-behaviour(gen_server).

-export([with/2, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% Private node-local admission service. Resource is any Erlang term; requests
%% for each resource are granted in server receive order. No timeouts or
%% cancellation protocol: an acquisition waits until granted or service death.
%% Never acquire the same resource recursively. Callers own all work/resources;
%% the server only monitors callers and transfers admission, never calls DETS.
with(Resource, Work) ->
    Pid = server(),
    Token = try gen_server:call(Pid, {acquire, Resource}, infinity)
            catch exit:Reason -> unavailable(Reason)
            end,
    try Work()
    after
        %% Address the exact generation, not its registered name. Async release
        %% cannot mask Work's exception if the service died in the meantime.
        gen_server:cast(Pid, {release, self(), Token})
    end.

unavailable(Reason) ->
    error({slate_dets_coordination_unavailable, Reason}).

server() ->
    case persistent_term:get(?MODULE, undefined) of
        undefined -> start();
        Pid -> Pid
    end.

start() ->
    %% The supervisor serializes start_child, including init. Unlike a global
    %% startup lock this has no randomized retry/backoff under contention.
    Child = #{id => ?MODULE, start => {?MODULE, start_link, []},
              restart => temporary, shutdown => 5000,
              type => worker, modules => [?MODULE]},
    try supervisor:start_child(kernel_safe_sup, Child) of
        {ok, Pid} -> Pid;
        {error, {already_started, Pid}} -> Pid;
        {error, Reason} -> unavailable(Reason)
    catch exit:Reason -> unavailable(Reason)
    end.

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    case persistent_term:get(?MODULE, undefined) of
        undefined ->
            %% One fixed VM-lifetime marker is necessary: old holders may
            %% still be executing after this service dies. Never erase it.
            %% Write INSIDE init, before acknowledging start. A caller that
            %% observed undefined before another start+crash must not start an
            %% empty replacement when its delayed start_child is processed.
            persistent_term:put(?MODULE, self()),
            {ok, #{resources => #{}, requests => #{}}};
        Pid -> {stop, {slate_dets_coordination_already_started, Pid}}
    end.

handle_call({acquire, Resource}, From = {Owner, _}, State) ->
    Token = monitor(process, Owner),
    Requests = (maps:get(requests, State))#{Token => {Resource, From}},
    Resources = maps:get(resources, State),
    case maps:find(Resource, Resources) of
        error ->
            Entry = #{holder => Token, waiters => queue:new()},
            {reply, Token, State#{resources := Resources#{Resource => Entry},
                                 requests := Requests}};
        {ok, Entry = #{waiters := Waiters}} ->
            Next = Entry#{waiters := queue:in(Token, Waiters)},
            {noreply, State#{resources := Resources#{Resource := Next},
                            requests := Requests}}
    end.

handle_cast({release, Owner, Token}, State) ->
    case maps:find(Token, maps:get(requests, State)) of
        {ok, {Resource, {Owner, _}}} ->
            #{holder := Token} = maps:get(Resource, maps:get(resources, State)),
            {noreply, remove(Token, State)};
        _ -> {noreply, State}
    end;
handle_cast(_Message, State) ->
    {noreply, State}.

handle_info({'DOWN', Token, process, _Pid, _Reason}, State) ->
    {noreply, remove(Token, State)};
handle_info(_Message, State) ->
    {noreply, State}.

remove(Token, State = #{resources := Resources, requests := Requests}) ->
    case maps:take(Token, Requests) of
        error -> State;
        {{Resource, _From}, Remaining} ->
            demonitor(Token, [flush]),
            Entry = maps:get(Resource, Resources),
            case Entry of
                #{holder := Token, waiters := Waiters} ->
                    case queue:out(Waiters) of
                        {empty, _} ->
                            State#{resources := maps:remove(Resource, Resources),
                                   requests := Remaining};
                        {{value, Next}, Rest} ->
                            {Resource, From} = maps:get(Next, Remaining),
                            gen_server:reply(From, Next),
                            State#{resources := Resources#{Resource :=
                                Entry#{holder := Next, waiters := Rest}},
                                   requests := Remaining}
                    end;
                #{waiters := Waiters} ->
                    %% Eagerly remove dead waiters, including their From/alias,
                    %% even if a holder remains alive indefinitely.
                    Live = queue:filter(fun(Ref) -> Ref =/= Token end, Waiters),
                    State#{resources := Resources#{Resource :=
                        Entry#{waiters := Live}}, requests := Remaining}
            end
    end.
