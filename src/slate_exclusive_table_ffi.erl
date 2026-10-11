-module(slate_exclusive_table_ffi).
-export([with_table/4]).

with_table(Path, Wait, Open, Callback) ->
    case deadline(Wait) of
        {error, Error} -> {error, {acquisition_failed, Error}};
        Deadline ->
            Caller = self(),
            Ref = make_ref(),
            {Guardian, Monitor} = spawn_monitor(fun() ->
                OwnerMonitor = monitor(process, Caller),
                watch_guardian(Path),
                case slate_lock_nif:ensure_loaded() of
                    {ok, nil} -> acquire(Caller, OwnerMonitor, Ref, Path, Deadline, Open);
                    {error, Error} -> Caller ! {Ref, {error, {acquisition_failed, Error}}}
                end
            end),
            receive
                {Ref, {opened, Table}} ->
                    Outcome = try Callback(Table) of
                        CallbackResult -> {returned, CallbackResult}
                    catch
                        Class:Reason:Stack -> {raised, Class, Reason, Stack}
                    end,
                    Guardian ! {Ref, {finish, Outcome}},
                    Result = receive_result(Ref, Monitor, Guardian, primary(Outcome)),
                    case Outcome of
                        {returned, _} -> Result;
                        {raised, ExceptionClass, ExceptionReason, Stacktrace} ->
                            erlang:raise(ExceptionClass, ExceptionReason, Stacktrace)
                    end;
                {Ref, {error, _} = Error} ->
                    Guardian ! {Ref, received},
                    demonitor(Monitor, [flush]),
                    Error;
                {'DOWN', Monitor, process, Guardian, Reason} ->
                    stopped(none, Reason)
            end
    end.

deadline(immediate) -> immediate;
deadline({wait_up_to, 0}) -> immediate;
deadline({wait_up_to, Milliseconds}) when is_integer(Milliseconds), Milliseconds > 0 ->
    erlang:monotonic_time(millisecond) + Milliseconds;
deadline({wait_up_to, Milliseconds}) -> {error, {invalid_wait, Milliseconds}}.

watch_guardian(Path) ->
    Guardian = self(),
    Watcher = spawn(fun() ->
        Monitor = monitor(process, Guardian),
        Guardian ! {self(), watching},
        receive
            {'DOWN', Monitor, process, Guardian, normal} -> ok;
            {'DOWN', Monitor, process, Guardian, Reason} ->
                logger:error(#{event => slate_exclusive_guardian_stopped,
                               path => Path, reason => Reason})
        end
    end),
    receive {Watcher, watching} -> ok end.

acquire(Caller, OwnerMonitor, Ref, Path, Deadline, Open) ->
    receive
        {'DOWN', OwnerMonitor, process, Caller, _} -> ok
    after 0 ->
        case expired(Deadline) of
            true -> Caller ! {Ref, {error, {acquisition_failed, timed_out}}};
            false ->
                case slate_lock_nif:acquire(Path) of
                    {ok, {Token, CanonicalPath}} ->
                        case expired(Deadline) of
                            true ->
                                Release = release(Token),
                                Reply = case Release of
                                    [] -> {error, {acquisition_failed, timed_out}};
                                    Failures -> {error, {cleanup_failed,
                                        {some, {acquisition_failure, timed_out}}, Failures}}
                                end,
                                reply(Caller, OwnerMonitor, Ref, Path, Reply);
                            false ->
                                owned(Caller, OwnerMonitor, Ref, CanonicalPath, Token, Open)
                        end;
                    {error, busy} when Deadline =:= immediate ->
                        Caller ! {Ref, {error, {acquisition_failed, busy}}};
                    {error, busy} ->
                        Delay = min(20, max(0, Deadline - erlang:monotonic_time(millisecond))),
                        receive
                            {'DOWN', OwnerMonitor, process, Caller, _} -> ok
                        after Delay -> acquire(Caller, OwnerMonitor, Ref, Path, Deadline, Open)
                        end;
                    {error, Error} -> Caller ! {Ref, {error, {acquisition_failed, Error}}}
                end
        end
    end.

expired(immediate) -> false;
expired(Deadline) -> erlang:monotonic_time(millisecond) >= Deadline.

owned(Caller, OwnerMonitor, Ref, Path, Token, Open) ->
    receive
        {'DOWN', OwnerMonitor, process, Caller, Reason} ->
            log_owner_cleanup(Path, release(Token), Reason)
    after 0 ->
        OpenResult = case existing_table(Path, dets:all()) of
            false -> Open(Path);
            true -> {error, slate_dets_ffi:translate_error({incompatible_arguments, Path})};
            {error, ExistingReason} -> {error, {unexpected_error, detail(ExistingReason)}}
        end,
        case OpenResult of
            {error, Error} ->
                Primary = {some, {open_failure, Error}},
                reply(Caller, OwnerMonitor, Ref, Path,
                      finalize(Primary, {error, Error}, release(Token)));
            {ok, Table} ->
                TablePid = dets:info(Table, pid),
                TableMonitor = monitor(process, TablePid),
                receive
                    {'DOWN', OwnerMonitor, process, Caller, Reason} ->
                        log_owner_cleanup(Path, cleanup(Table, TablePid, TableMonitor, Token), Reason)
                after 0 ->
                    Caller ! {Ref, {opened, Table}},
                    receive
                        {Ref, {finish, Outcome}} ->
                            Failures = cleanup(Table, TablePid, TableMonitor, Token),
                            Result = finalize(primary(Outcome), callback_result(Outcome), Failures),
                            case Outcome of
                                {raised, Class, Reason, _} ->
                                    log_exception_cleanup(Path, Result, Class, Reason);
                                {returned, _} -> ok
                            end,
                            reply(Caller, OwnerMonitor, Ref, Path, Result);
                        {'DOWN', OwnerMonitor, process, Caller, Reason} ->
                            log_owner_cleanup(Path, cleanup(Table, TablePid, TableMonitor, Token), Reason)
                    end
                end
        end
    end.

existing_table(_Path, []) -> false;
existing_table(Path, [Table | Rest]) ->
    case dets:info(Table, filename) of
        undefined -> existing_table(Path, Rest);
        Filename ->
            Binary = case os:type() of
                {win32, _} -> unicode:characters_to_binary(Filename);
                {unix, _} -> list_to_binary(Filename)
            end,
            case slate_lock_nif:resolve(Binary) of
                {ok, Path} -> true;
                {ok, _} -> existing_table(Path, Rest);
                {error, Error} -> {error, Error}
            end
    end.

cleanup(Table, TablePid, TableMonitor, Token) ->
    case slate_dets_ffi:close(Table) of
        {error, Error} ->
            demonitor(TableMonitor, [flush]),
            [{close_failure, Error}];
        {ok, nil} ->
            case dets:info(Table, pid) of
                TablePid ->
                    demonitor(TableMonitor, [flush]),
                    [{close_failure, {unexpected_error, <<"exclusive_table_still_open">>}}];
                _ ->
                    receive {'DOWN', TableMonitor, process, TablePid, _} -> release(Token) end
            end
    end.

release(Token) ->
    case slate_lock_nif:release(Token) of
        {ok, nil} -> [];
        {error, Error} -> [{release_failure, Error}]
    end.

primary({returned, {error, Error}}) -> {some, {callback_failure, Error}};
primary({returned, {ok, _}}) -> none;
primary({raised, _, _, _}) -> none.

callback_result({returned, Result}) -> Result;
callback_result({raised, _, _, _}) -> {ok, nil}.

finalize(none, {ok, Value}, []) -> {ok, Value};
finalize({some, Failure}, {error, _}, []) -> {error, {session_failed, Failure}};
finalize(Primary, _Result, Failures) -> {error, {cleanup_failed, Primary, Failures}}.

receive_result(Ref, Monitor, Guardian, Primary) ->
    receive
        {Ref, Result} ->
            Guardian ! {Ref, received},
            demonitor(Monitor, [flush]),
            Result;
        {'DOWN', Monitor, process, Guardian, Reason} -> stopped(Primary, Reason)
    end.

%% A cleanup error must either reach the caller or enter Logger.
reply(Caller, OwnerMonitor, Ref, Path, Result) ->
    Caller ! {Ref, Result},
    receive
        {Ref, received} -> ok;
        {'DOWN', OwnerMonitor, process, Caller, Reason} ->
            case Result of
                {error, {cleanup_failed, _, _} = Error} ->
                    logger:error(#{event => slate_exclusive_cleanup_failed,
                                   path => Path, owner_exit => Reason, error => Error});
                {ok, _} -> ok;
                {error, {session_failed, _}} -> ok;
                {error, {acquisition_failed, _}} -> ok
            end
    end.

stopped(Primary, Reason) ->
    {error, {cleanup_failed, Primary, [{guardian_stopped, detail(Reason)}]}}.

log_owner_cleanup(_Path, [], _Reason) -> ok;
log_owner_cleanup(Path, Failures, Reason) ->
    logger:error(#{event => slate_exclusive_cleanup_failed,
                   path => Path, owner_exit => Reason, failures => Failures}).

log_exception_cleanup(_Path, {ok, _}, _Class, _Reason) -> ok;
log_exception_cleanup(Path, {error, Error}, Class, Reason) ->
    logger:error(#{event => slate_exclusive_cleanup_failed,
                   path => Path, exception_class => Class, exception_reason => Reason,
                   error => Error}).

detail(Reason) -> unicode:characters_to_binary(io_lib:format("~tp", [Reason])).
