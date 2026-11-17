-module(test_helpers_ffi).
-export([did_panic/1, identity/1, is_table_open/1,
         write_raw_objects/3, read_raw_objects/1]).

%% Shared by sequential raw-fixture readers and writers; never derive atoms
%% from paths. Call only while the fixture is closed by the public API.
-define(RAW_OBJECTS_TABLE, slate_test_raw_objects).

%% Gleam test constructors Set/Bag/DuplicateBag are these zero-arity atoms.
%% Objects are caller-supplied tuples, including intentionally malformed pairs.
write_raw_objects(Path, Type, Objects)
        when Type =:= set; Type =:= bag; Type =:= duplicate_bag ->
    with_raw_objects(Path, [{type, Type}], fun(Name) ->
        try dets:insert(Name, Objects) of
            ok -> {ok, nil};
            {error, _} = Error -> Error
        catch
            error:badarg -> {error, badarg}
        end
    end).

read_raw_objects(Path) ->
    with_raw_objects(Path, [{access, read}], fun(Name) ->
        case dets:foldl(fun(Object, Acc) -> [Object | Acc] end, [], Name) of
            {error, _} = Error -> Error;
            Objects -> {ok, Objects}
        end
    end).

with_raw_objects(Path, Options, Work) ->
    Filename = unicode:characters_to_list(Path),
    case dets:open_file(?RAW_OBJECTS_TABLE, [{file, Filename} | Options]) of
        {ok, Name} ->
            try
                try Work(Name)
                after
                    %% Close even if Work raises, and expose close errors as
                    %% Results rather than discarding them in the after clause.
                    case dets:close(Name) of
                        ok -> ok;
                        {error, Reason} ->
                            throw({raw_objects_close_error, Reason})
                    end
                end
            catch
                throw:{raw_objects_close_error, CloseReason} ->
                    {error, CloseReason}
            end;
        {error, _} = Error -> Error
    end.

%% Unsafe identity function used by test_helper.unsafe_decoder/0
%% to bypass type checking in tests with complex value types.
identity(X) -> X.

did_panic(Callback) ->
    try
        _ = Callback(),
        false
    catch
        _:_ -> true
    end.

is_table_open(Path) ->
    CanonicalPath = slate_dets_ffi:canonicalize_path(Path),
    lists:any(
        fun(Name) ->
            case dets:info(Name, filename) of
                undefined -> false;
                OpenPath -> slate_dets_ffi:canonicalize_path(OpenPath) =:= CanonicalPath
            end
        end,
        dets:all()
    ).
