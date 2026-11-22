-module(slate_dets_lifetime).
-behaviour(gen_server).

-export([find/1, available/2, begin_open/2, opened/2, failed/1, path/1,
         await_idle/0, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(entry, {name, pids = #{}, pending = 0, identities = []}).
-record(opening, {path, owner_monitor, fence_pid = undefined,
                  fence_monitor = undefined, reply = undefined}).
-record(state, {paths = #{}, names = #{}, openings = #{}, monitors = #{},
                idle_waiters = #{}}).

%% DETS removes a name from its registry BEFORE finishing the final close,
%% including close on owner death. Retain path -> name until all observed
%% servers and in-flight opens are finished. These are reservations, not a cache:
%% rebuilding from dets:all() after losing this state would be unsafe.
find(Path) -> call({find, Path, slate_dets_ffi:file_identity(Path)}).
available(Name, Path) -> call({available, Name, Path, slate_dets_ffi:file_identity(Path)}).
begin_open(Path, Name) -> call({begin_open, Path, Name, slate_dets_ffi:file_identity(Path)}).
%% Called under open_admission before selection, never under a mutation gate.
%% A dead opener may still create/repair a file before its fence completes.
await_idle() -> call(await_idle).
opened(Token, Pid) when is_pid(Pid) -> call({opened, Token, Pid});
opened(Token, undefined) -> failed(Token).
failed(Token) -> call({failed, Token}).
path(Name) -> call({path, Name}).

call(Request) ->
    Pid = server(),
    try gen_server:call(Pid, Request, infinity)
    catch exit:Reason -> error({slate_dets_lifetime_unavailable, Reason})
    end.

server() ->
    case persistent_term:get(?MODULE, undefined) of
        undefined ->
            global:trans({{?MODULE, start}, self()}, fun start/0, [node()]);
        Pid -> Pid
    end.

start() ->
    case persistent_term:get(?MODULE, undefined) of
        undefined ->
            %% Like DETS itself, this VM-wide service belongs to kernel_safe_sup,
            %% not to whichever application/process happens to open first.
            Child = #{id => ?MODULE, start => {?MODULE, start_link, []},
                      restart => temporary, shutdown => 5000,
                      type => worker, modules => [?MODULE]},
            Pid = case supervisor:start_child(kernel_safe_sup, Child) of
                {ok, Started} -> Started;
                {error, {already_started, Started}} -> Started;
                {error, Reason} -> error({slate_dets_lifetime_unavailable, Reason})
            end,
            %% One fixed VM-lifetime marker, not per-path persistent terms.
            %% Never erase/restart after failure: unknown closing files must
            %% not be opened by a fresh, empty allocator. Close remains usable.
            persistent_term:put(?MODULE, Pid),
            Pid;
        Pid -> Pid
    end.

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) -> {ok, #state{}}.

handle_call(await_idle, From, State) when map_size(State#state.openings) > 0 ->
    {Caller, _} = From,
    Ref = monitor(process, Caller),
    {noreply, State#state{
        idle_waiters = (State#state.idle_waiters)#{Ref => From},
        monitors = (State#state.monitors)#{Ref => idle_waiter}}};
handle_call(await_idle, _From, State) ->
    {reply, ok, State};
handle_call({find, Path, Identity}, _From, State) ->
    Reply = case find_entry(Path, Identity, State) of
        {ok, _, #entry{name = Name}} -> {ok, Name};
        error -> error
    end,
    {reply, Reply, State};
handle_call({path, Name}, _From, State) ->
    {reply, maps:find(Name, State#state.names), State};
handle_call({available, Name, Path, Identity}, _From, State) ->
    {reply, available_in(Name, Path, Identity, State), State};
handle_call({begin_open, Path, Proposed, Identity}, {Owner, _}, State) ->
    case find_entry(Path, Identity, State) of
        {ok, ReservedPath, Entry} -> reserve(ReservedPath, Entry, Owner, State);
        error ->
            case available_in(Proposed, Path, Identity, State) of
                true ->
                    Entry = add_identity(Identity, #entry{name = Proposed}),
                    reserve(Path, Entry, Owner, State);
                false -> {reply, busy, State}
            end
    end;
handle_call({opened, Token, Pid}, _From, State) ->
    {reply, ok, complete(Token, Pid, State)};
handle_call({failed, Token}, From, State) ->
    %% No blocking DETS calls in the registry callback. A non-owner close is a
    %% fence in dets_server's per-name request queue, including pending close.
    {noreply, start_fence(Token, From, State)}.

handle_cast(_Message, State) -> {noreply, State}.

handle_info({fenced, Worker, Token, Pid}, State) ->
    #opening{fence_pid = Worker, reply = Reply} =
        maps:get(Token, State#state.openings),
    Next = complete(Token, Pid, State),
    case Reply of
        undefined -> ok;
        _ -> gen_server:reply(Reply, ok)
    end,
    {noreply, Next};
handle_info({'DOWN', Ref, process, Pid, Reason}, State) ->
    case maps:take(Ref, State#state.monitors) of
        error -> {noreply, State};
        {idle_waiter, Monitors} ->
            {noreply, State#state{monitors = Monitors,
                                 idle_waiters = maps:remove(Ref, State#state.idle_waiters)}};
        {{opener, Token}, Monitors} ->
            %% The caller may have died before reporting the returned PID.
            %% Keep its reservation until a non-owner fence has observed all
            %% preceding work for this name and any remaining live server.
            {noreply, start_fence(Token, undefined, State#state{monitors = Monitors})};
        {{table, Path, Pid}, Monitors} ->
            Entry = maps:get(Path, State#state.paths),
            Pids = maps:remove(Pid, Entry#entry.pids),
            Paths = (State#state.paths)#{Path => Entry#entry{pids = Pids}},
            {noreply, prune(Path, State#state{paths = Paths, monitors = Monitors})};
        {{fence, _Token}, _Monitors} ->
            %% A failed fence leaves lifetime uncertain. The persistent marker
            %% makes this a fail-closed service failure, never a freed slot.
            {stop, {lifetime_fence_failed, Reason}, State}
    end.

find_entry(Path, Identity, State) ->
    case maps:find(Path, State#state.paths) of
        {ok, Entry} -> {ok, Path, Entry};
        error -> find_identity(maps:to_list(State#state.paths), Identity)
    end.

find_identity(_, none) -> error;
find_identity([], _Identity) -> error;
find_identity([{Path, Entry} | Rest], Identity) ->
    case lists:member(Identity, Entry#entry.identities) of
        true -> {ok, Path, Entry};
        false -> find_identity(Rest, Identity)
    end.

available_in(Name, Path, Identity, State) ->
    case maps:find(Name, State#state.names) of
        error -> true;
        {ok, ReservedPath} ->
            case find_entry(Path, Identity, State) of
                {ok, ReservedPath, _} -> true;
                _ -> false
            end
    end.

reserve(Path, Entry, Owner, State) ->
    Token = make_ref(),
    Ref = monitor(process, Owner),
    Opening = #opening{path = Path, owner_monitor = Ref},
    Next = State#state{
        paths = (State#state.paths)#{Path => Entry#entry{pending = Entry#entry.pending + 1}},
        names = (State#state.names)#{Entry#entry.name => Path},
        openings = (State#state.openings)#{Token => Opening},
        monitors = (State#state.monitors)#{Ref => {opener, Token}}},
    {reply, {ok, Token, Entry#entry.name, maps:keys(Entry#entry.pids)}, Next}.

start_fence(Token, Reply, State) ->
    Opening = maps:get(Token, State#state.openings),
    Path = Opening#opening.path,
    #entry{name = Name} = maps:get(Path, State#state.paths),
    OwnerRef = Opening#opening.owner_monitor,
    demonitor(OwnerRef, [flush]),
    Parent = self(),
    {Pid, Ref} = spawn_monitor(fun() ->
        TablePid = fenced_pid(Name, Path),
        Parent ! {fenced, self(), Token, TablePid}
    end),
    NextOpening = Opening#opening{fence_pid = Pid, fence_monitor = Ref, reply = Reply},
    State#state{
        openings = (State#state.openings)#{Token => NextOpening},
        monitors = (maps:remove(OwnerRef, State#state.monitors))#{Ref => {fence, Token}}}.

fenced_pid(Name, Path) ->
    {error, not_owner} = dets:close(Name),
    %% Owner death can reach DETS AFTER the first fence. Capture a live PID
    %% before any blocking filename query. If the registry already vanished,
    %% another fence must drain the newly pending close before releasing Name.
    case dets:info(Name, owner) of
        undefined ->
            {error, not_owner} = dets:close(Name),
            undefined;
        Pid ->
            case dets:info(Name, filename) of
                undefined -> Pid;
                Filename ->
                    case slate_dets_ffi:same_file(canonical_filename(Filename), Path) of
                        true -> Pid;
                        false -> undefined
                    end
            end
    end.

canonical_filename(Filename) when is_binary(Filename) ->
    slate_dets_ffi:canonicalize_path(unicode:characters_to_list(Filename));
canonical_filename(Filename) ->
    slate_dets_ffi:canonicalize_path(Filename).

complete(Token, Pid, State) ->
    {Opening, Openings} = maps:take(Token, State#state.openings),
    Path = Opening#opening.path,
    Monitors = remove_monitor(Opening#opening.fence_monitor,
        remove_monitor(Opening#opening.owner_monitor, State#state.monitors)),
    %% Auto/force repair can rename a new inode over just this directory entry.
    %% Retain BOTH observations until every PID and pending open is gone.
    Entry = add_identity(slate_dets_ffi:file_identity(Path),
                         maps:get(Path, State#state.paths)),
    {Tracked, NextMonitors} = track(Path, Entry, Pid, Monitors),
    Paths = (State#state.paths)#{Path => Tracked#entry{pending = Entry#entry.pending - 1}},
    Next = prune(Path, State#state{paths = Paths, openings = Openings, monitors = NextMonitors}),
    case map_size(Openings) of
        0 ->
            IdleMonitors = maps:fold(fun(Ref, From, Acc) ->
                gen_server:reply(From, ok),
                remove_monitor(Ref, Acc)
            end, Next#state.monitors, Next#state.idle_waiters),
            Next#state{idle_waiters = #{}, monitors = IdleMonitors};
        _ -> Next
    end.

add_identity(none, Entry) -> Entry;
add_identity(Identity, Entry) ->
    Entry#entry{identities = lists:usort([Identity | Entry#entry.identities])}.

track(_Path, Entry, undefined, Monitors) -> {Entry, Monitors};
track(Path, Entry, Pid, Monitors) ->
    %% A fence can report an older generation AFTER a replacement registered.
    %% Completion only adds evidence; it never replaces another PID's monitor.
    %% Even an already-dead PID gets its own DOWN, which removes only that PID.
    case maps:is_key(Pid, Entry#entry.pids) of
        true -> {Entry, Monitors};
        false ->
            Ref = monitor(process, Pid),
            Pids = (Entry#entry.pids)#{Pid => Ref},
            {Entry#entry{pids = Pids}, Monitors#{Ref => {table, Path, Pid}}}
    end.

remove_monitor(undefined, Monitors) -> Monitors;
remove_monitor(Ref, Monitors) ->
    demonitor(Ref, [flush]),
    maps:remove(Ref, Monitors).

prune(Path, State) ->
    case maps:get(Path, State#state.paths) of
        #entry{name = Name, pids = Pids, pending = 0} when map_size(Pids) =:= 0 ->
            State#state{paths = maps:remove(Path, State#state.paths),
                        names = maps:remove(Name, State#state.names)};
        #entry{} -> State
    end.
