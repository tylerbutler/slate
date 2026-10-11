-module(slate_lock_nif).
-export([ensure_loaded/0, acquire/1, release/1, resolve/1, target/0]).

%% Do not use on_load: missing native files must not disable unlocked APIs.
ensure_loaded() ->
    case target() of
        {error, _} = Error -> Error;
        {ok, Target} ->
            case native_directory() of
                {ok, Directory} ->
                    Path = filename:join([Directory, Target, "slate_lock"]),
                    case erlang:load_nif(Path, 0) of
                        ok -> {ok, nil};
                        {error, {reload, _}} -> {ok, nil};
                        {error, Reason} ->
                            {error, {native_unavailable, detail(Reason)}}
                    end;
                {error, Reason} ->
                    {error, {native_unavailable, detail(Reason)}}
            end
    end.

native_directory() ->
    case code:priv_dir(slate) of
        {error, bad_name} ->
            case init:get_argument(escript) of
                {ok, _} ->
                    {ok, filename:join(filename:dirname(filename:absname(escript:script_name())),
                                      "slate_native")};
                error -> {error, native_directory_not_found}
            end;
        Directory -> {ok, filename:join(Directory, "slate_lock")}
    end.

target() ->
    Architecture = erlang:system_info(system_architecture),
    Cpu = hd(string:split(Architecture, "-")),
    case {os:type(), Cpu} of
        {{unix, linux}, "x86_64"} -> linux_target(Cpu, Architecture);
        {{unix, linux}, "aarch64"} -> linux_target(Cpu, Architecture);
        {{unix, darwin}, "x86_64"} -> {ok, "x86_64-apple-darwin"};
        {{unix, darwin}, "aarch64"} -> {ok, "aarch64-apple-darwin"};
        {{unix, darwin}, "arm64"} -> {ok, "aarch64-apple-darwin"};
        {{win32, _}, "win32"} -> windows_target();
        {{win32, _}, "x86_64"} -> windows_target();
        _ -> {error, {unsupported_platform, detail({os:type(), Architecture})}}
    end.

windows_target() ->
    case {erlang:system_info(wordsize), os:getenv("PROCESSOR_ARCHITECTURE")} of
        {8, "AMD64"} -> {ok, "x86_64-pc-windows"};
        Details -> {error, {unsupported_platform, detail({windows, Details})}}
    end.

linux_target(Cpu, Architecture) ->
    case lists:member("gnu", string:split(Architecture, "-", all)) of
        true -> {ok, Cpu ++ "-linux-gnu"};
        false -> {error, {unsupported_platform, detail({linux, Architecture})}}
    end.

detail(Reason) ->
    unicode:characters_to_binary(io_lib:format("~tp", [Reason])).

acquire(_Path) -> erlang:nif_error(native_not_loaded).
release(_Token) -> erlang:nif_error(native_not_loaded).
resolve(_Path) -> erlang:nif_error(native_not_loaded).
