-module(slate_exclusive_vm_fixture).
-export([main/0]).

main() ->
    true = register(exclusive_fixture_main, self()),
    ok = logger:add_handler(exclusive_fixture_capture, exclusive_test_logger,
                            #{level => error, config => #{owner => self()}}),
    emit(ready),
    loop(undefined).

loop(Owner) ->
    case command() of
        {session, Path, Type, Wait, Action} ->
            await_owner(Owner),
            Main = self(),
            Next = spawn_session(Main, Path, Type, auto_repair, read_write, Wait, Action),
            loop(Next);
        {session_with, Path, Type, Repair, Access, Wait, Action} ->
            await_owner(Owner),
            Next = spawn_session(self(), Path, Type, Repair, Access, Wait, Action),
            loop(Next);
        {inject_release_failure, Mode} ->
            ok = exclusive_fault_ffi:inject(Mode),
            emit(fault_injected),
            loop(Owner);
        await_delivery ->
            receive {delivery_paused, Owner} -> emit(delivery_paused)
            after 5000 -> error(delivery_not_paused) end,
            loop(Owner);
        {finish, Action} -> Owner ! {finish, Action}, loop(Owner);
        kill_owner -> exit(Owner, kill), emit(owner_killed), loop(Owner);
        kill_guardian ->
            Guardian = receive {guardian, Pid} -> Pid after 5000 -> error(missing_guardian) end,
            exit(Guardian, kill),
            emit(guardian_killed),
            loop(Owner);
        continue_open ->
            Guardian = receive {guardian, Pid} -> Pid after 5000 -> error(missing_guardian) end,
            Guardian ! continue_open,
            loop(Owner);
        await_close ->
            Guardian = receive {guardian, Pid} -> Pid after 5000 -> error(missing_guardian) end,
            self() ! {guardian, Guardian},
            await_close(Guardian, erlang:monotonic_time(millisecond) + 5000),
            emit(close_waiting),
            loop(Owner);
        pause_table ->
            {TablePid, Callback} = receive {pause_table, Pid, Process} -> {Pid, Process}
                                  after 5000 -> error(missing_table_pid) end,
            true = erlang:suspend_process(TablePid),
            self() ! {table_pid, TablePid},
            Callback ! table_suspended,
            emit(close_blocked),
            loop(Owner);
        resume_table ->
            TablePid = receive {table_pid, Pid} -> Pid after 5000 -> error(missing_table_pid) end,
            true = erlang:resume_process(TablePid),
            emit(table_resumed),
            loop(Owner);
        get_log ->
            Report = receive {captured_log, Log} -> Log after 5000 -> error(missing_cleanup_log) end,
            emit({log, Report}),
            loop(Owner);
        stop_extra ->
            Extra = receive {extra, Pid} -> Pid after 5000 -> error(missing_extra_owner) end,
            Extra ! stop,
            emit(extra_stopped),
            loop(Owner);
        halt_vm -> erlang:halt(70);
        stop -> erlang:halt(0)
    end.

await_owner(undefined) -> ok;
await_owner(Owner) ->
    Monitor = monitor(process, Owner),
    receive {'DOWN', Monitor, process, Owner, _} -> ok
    after 5000 -> error(previous_session_still_running) end.

spawn_session(Main, Path, Type, Repair, Access, Wait, Action) ->
    spawn(fun() ->
        Owner = self(),
        put(exclusive_fixture_owner, Owner),
        Result = try
            'slate@internal@exclusive_session':with_table(
                Path, Wait,
                fun(Canonical) ->
                    emit(opening),
                    case Action of
                        block_open ->
                            Main ! {guardian, self()},
                            emit(open_blocked),
                            receive continue_open -> ok end;
                        _ -> ok
                    end,
                    apply(slate_dets_ffi, open_function(Type), [Canonical, Repair, Access])
                end,
                fun(Table) ->
                    Owner = self(),
                    Owner = get(exclusive_fixture_owner),
                    action(Table, Action, Main)
                end)
        catch
            Class:Reason -> {exception, Class, Reason}
        end,
        emit({result, Result})
    end).

open_function(set) -> open_exclusive_set;
open_function(bag) -> open_exclusive_bag;
open_function(duplicate_bag) -> open_exclusive_duplicate_bag.

action(Table, hold, Main) ->
    {monitors, [{process, Guardian}]} = process_info(self(), monitors),
    Main ! {guardian, Guardian},
    emit(holding),
    receive {finish, Next} -> action(Table, Next, Main) end;
action(Table, {insert, Key, Value}, _Main) ->
    slate_dets_ffi:insert(Table, [{Key, Value}]);
action(Table, {lookup, Key}, _Main) -> slate_dets_ffi:lookup(Table, Key);
action(Table, {lookup_all, Key}, _Main) -> slate_dets_ffi:lookup_all(Table, Key);
action(Table, {increment, Key}, _Main) ->
    Value = case slate_dets_ffi:lookup(Table, Key) of
        {ok, Old} -> Old;
        {error, not_found} -> 0
    end,
    slate_dets_ffi:insert(Table, [{Key, Value + 1}]);
action(Table, {insert_then_error, Key, Value}, _Main) ->
    {ok, nil} = slate_dets_ffi:insert(Table, [{Key, Value}]),
    {error, not_found};
action(_Table, return_ok, _Main) -> {ok, nil};
action(_Table, return_error, _Main) -> {error, not_found};
action(_Table, block_open, _Main) -> error(blocked_open_callback_ran);
action(Table, block_close, Main) ->
    {monitors, [{process, Guardian}]} = process_info(self(), monitors),
    TablePid = dets:info(slate_dets_ffi:table_name(Table), pid),
    Main ! {guardian, Guardian},
    Main ! {pause_table, TablePid, self()},
    emit(close_ready),
    receive table_suspended -> ok end,
    {ok, nil};
action(Table, kill_table_then_error, _Main) ->
    TablePid = dets:info(slate_dets_ffi:table_name(Table), pid),
    Monitor = monitor(process, TablePid),
    exit(TablePid, kill),
    receive {'DOWN', Monitor, process, TablePid, killed} -> ok end,
    {error, not_found};
action(_Table, {raise, Class}, _Main) ->
    case Class of
        error -> erlang:error(exclusive_fixture_exception);
        throw -> erlang:throw(exclusive_fixture_exception);
        exit -> erlang:exit(exclusive_fixture_exception)
    end;
action(Table, add_user_then_raise, Main) ->
    add_user(Table, Main),
    erlang:error(exclusive_fixture_exception);
action(Table, add_user_then_hold, Main) ->
    add_user(Table, Main),
    action(Table, hold, Main);
action(Table, add_user_then_error, Main) ->
    add_user(Table, Main),
    {error, not_found}.

add_user(Table, Main) ->
    Name = slate_dets_ffi:table_name(Table),
    Path = dets:info(Name, filename),
    Caller = self(),
    Extra = spawn(fun() ->
        {ok, Name} = dets:open_file(Name, [{file, Path}]),
        Caller ! extra_open,
        receive stop -> ok = dets:close(Name) end
    end),
    receive extra_open -> ok after 5000 -> error(extra_open_timeout) end,
    Main ! {extra, Extra}.

await_close(Guardian, Deadline) ->
    {current_stacktrace, Stack} = process_info(Guardian, current_stacktrace),
    case lists:any(fun
        ({slate_dets_ffi, close, _, _}) -> true;
        (_) -> false
    end, Stack) of
        true -> ok;
        false ->
            case erlang:monotonic_time(millisecond) >= Deadline of
                true -> error(close_phase_timeout);
                false -> receive after 1 -> await_close(Guardian, Deadline) end
            end
    end.

command() ->
    case io:get_line("") of
        eof -> erlang:halt(0);
        Line ->
            {ok, Tokens, _} = erl_scan:string(Line),
            {ok, Term} = erl_parse:parse_term(Tokens),
            Term
    end.

emit(Term) -> io:format("SLATE ~w~n", [Term]).
