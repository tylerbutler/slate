-module(test_helpers_ffi).
-export([did_panic/1, identity/1, is_table_open/1]).

%% Unsafe identity function used by test_helpers.unsafe_decoder/0
%% to bypass type checking in tests with complex value types.
identity(X) -> X.

did_panic(Fun) ->
    try
        _ = Fun(),
        false
    catch
        _:_ -> true
    end.

is_table_open(Path) ->
    CanonicalPath = canonicalize_path(Path),
    lists:any(
        fun(Name) ->
            case dets:info(Name, filename) of
                undefined -> false;
                OpenPath -> canonicalize_path(OpenPath) =:= CanonicalPath
            end
        end,
        dets:all()
    ).

canonicalize_path(Path) when is_binary(Path) ->
    filename:absname(binary_to_list(Path));
canonicalize_path(Path) when is_list(Path) ->
    filename:absname(Path).
