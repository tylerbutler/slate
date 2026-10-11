#!/usr/bin/env escript
%%! -noshell

main([]) ->
    Root = filename:dirname(filename:dirname(filename:absname(escript:script_name()))),
    Repo = filename:dirname(filename:dirname(Root)),
    Loader = filename:join([Repo, "src", "slate_lock_nif.erl"]),
    {ok, slate_lock_nif, Beam} = compile:file(Loader, [binary, report_errors, report_warnings]),
    {module, slate_lock_nif} = code:load_binary(slate_lock_nif, Loader, Beam),
    Target = case slate_lock_nif:target() of
        {ok, Supported} -> Supported;
        {error, Error} -> io:format(standard_error, "~tp~n", [Error]), halt(1)
    end,
    RustTarget = rust_target(Target),
    Manifest = filename:join([Root, "source", "Cargo.toml"]),
    Build = filename:join([Repo, "build", "native"]),
    Directory = filename:join(Root, Target),
    ok = filelib:ensure_dir(filename:join(Directory, "placeholder")),
    {Library, Output} = case os:type() of
        {win32, _} -> {"slate_lock.dll", "slate_lock.dll"};
        {unix, darwin} -> {"libslate_lock.dylib", "slate_lock.so"};
        {unix, linux} -> {"libslate_lock.so", "slate_lock.so"}
    end,
    Args = ["build", "--release", "--locked", "--manifest-path", Manifest,
            "--target-dir", Build, "--target", RustTarget],
    case os:find_executable("cargo") of
        false -> io:format(standard_error, "Rust/Cargo 1.91 or later is required.~n", []), halt(1);
        Executable ->
            Port = open_port({spawn_executable, Executable},
                             [binary, exit_status, use_stdio, stderr_to_stdout,
                              {cd, filename:dirname(Manifest)}, {args, Args}]),
            case wait(Port) of
                0 ->
                    {ok, _} = file:copy(filename:join([Build, RustTarget, "release", Library]),
                                       filename:join(Directory, Output));
                Status -> halt(Status)
            end
    end;
main(_) ->
    io:format(standard_error, "Usage: escript priv/slate_lock/source/build.escript~n", []),
    halt(1).

rust_target("x86_64-linux-gnu") -> "x86_64-unknown-linux-gnu";
rust_target("aarch64-linux-gnu") -> "aarch64-unknown-linux-gnu";
rust_target("x86_64-apple-darwin") -> "x86_64-apple-darwin";
rust_target("aarch64-apple-darwin") -> "aarch64-apple-darwin";
rust_target("x86_64-pc-windows") -> "x86_64-pc-windows-msvc".

wait(Port) ->
    receive
        {Port, {data, Data}} -> io:put_chars(Data), wait(Port);
        {Port, {exit_status, Status}} -> Status
    end.
