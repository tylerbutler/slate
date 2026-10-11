-module(exclusive_fault_ffi).
-export([inject/1, acquire/1, release/1]).

inject(Mode) ->
    Beam = code:which(slate_exclusive_table_ffi),
    Source = filename:join([filename:dirname(filename:dirname(Beam)), "_gleam_artefacts",
                            "slate_exclusive_table_ffi.erl"]),
    {ok, Forms} = epp:parse_file(Source, [], []),
    Rewritten = rewrite(Forms, Mode),
    {ok, slate_exclusive_table_ffi, Binary} = compile:forms(Rewritten, [binary]),
    {module, slate_exclusive_table_ffi} =
        code:load_binary(slate_exclusive_table_ffi, Source, Binary),
    ok.

rewrite({remote, Line, {atom, ModuleLine, slate_lock_nif}, {atom, FunctionLine, Function}},
        Mode) when Function =:= release, Mode =/= late_acquire_success;
                   Function =:= acquire, Mode =:= late_acquire;
                   Function =:= acquire, Mode =:= late_acquire_success ->
    {remote, Line, {atom, ModuleLine, ?MODULE}, {atom, FunctionLine, Function}};
rewrite(Tuple, Mode) when is_tuple(Tuple) ->
    list_to_tuple([rewrite(Element, Mode) || Element <- tuple_to_list(Tuple)]);
rewrite(List, Mode) when is_list(List) -> [rewrite(Element, Mode) || Element <- List];
rewrite(Value, _Mode) -> Value.

acquire(Path) ->
    Result = slate_lock_nif:acquire(Path),
    receive after 100 -> Result end.

release(_Token) ->
    {error, {os_failure, {file_error_context, none, <<"injected_release_failure">>}}}.
