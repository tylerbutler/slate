-module(exclusive_fault_ffi).
-export([inject/1, acquire/1, release/1, send/2]).

inject(Mode) ->
    Module = 'slate@internal@exclusive_session',
    Beam = code:which(Module),
    %% Gleam 1.19 emits abstract forms directly rather than an .erl source file.
    {ok, {Module, [{abstract_code, {raw_abstract_v1, Forms}}]}} =
        beam_lib:chunks(Beam, [abstract_code]),
    Rewritten = rewrite(Forms, Mode),
    {ok, Module, Binary} = compile:forms(Rewritten, [binary]),
    {module, Module} = code:load_binary(Module, Beam, Binary),
    ok.

rewrite({remote, Line, {atom, ModuleLine, slate_lock_nif}, {atom, FunctionLine, Function}},
        Mode) when Function =:= release, Mode =/= late_acquire_success;
                   Function =:= acquire, Mode =:= late_acquire;
                   Function =:= acquire, Mode =:= late_acquire_success ->
    {remote, Line, {atom, ModuleLine, ?MODULE}, {atom, FunctionLine, Function}};
rewrite({remote, Line, {atom, ModuleLine, 'gleam@erlang@process'}, {atom, FunctionLine, send}},
        pause_delivery) ->
    {remote, Line, {atom, ModuleLine, ?MODULE}, {atom, FunctionLine, send}};
rewrite(Tuple, Mode) when is_tuple(Tuple) ->
    list_to_tuple([rewrite(Element, Mode) || Element <- tuple_to_list(Tuple)]);
rewrite(List, Mode) when is_list(List) -> [rewrite(Element, Mode) || Element <- List];
rewrite(Value, _Mode) -> Value.

acquire(Path) ->
    Result = slate_lock_nif:acquire(Path),
    receive after 1100 -> Result end.

release(_Token) ->
    {error, {os_failure, {file_error_context, none, <<"injected_release_failure">>}}}.

send(Subject = {subject, Owner, _}, {error, {cleanup_failed, _, _}} = Reply) ->
    true = erlang:suspend_process(Owner),
    'gleam@erlang@process':send(Subject, Reply),
    whereis(exclusive_fixture_main) ! {delivery_paused, Owner},
    nil;
send(Subject, Message) -> 'gleam@erlang@process':send(Subject, Message).
