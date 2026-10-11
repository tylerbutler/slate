#!/usr/bin/env escript
%%! -noshell +S 2:2 +A 1
-mode(compile).

main(["--release-artifacts"]) ->
    lists:foreach(fun require_artifact/1, targets()),
    io:format("All five native artifacts are present.~n");
main([]) ->
    {ok, Cwd} = file:get_cwd(),
    Root = filename:join([Cwd, "build", "exclusive-package-" ++
                         integer_to_list(erlang:system_time(nanosecond))]),
    ok = filelib:ensure_dir(filename:join(Root, "placeholder")),
    try
        run("gleam", ["export", "hex-tarball"], Cwd),
        {ok, Toml} = file:read_file(filename:join(Cwd, "gleam.toml")),
        {match, [Version]} = re:run(Toml, <<"(?m)^version = \"([^\"]+)\"">>,
                                  [{capture, [1], list}]),
        Archive = filename:join([Cwd, "build", "slate-" ++ Version ++ ".tar"]),
        true = filelib:file_size(Archive) < 8 * 1024 * 1024,
        {ok, Outer} = erl_tar:extract(Archive, [memory]),
        Contents = proplists:get_value("contents.tar.gz", Outer),
        true = is_binary(Contents),
        Package = filename:join(Root, "package"),
        ok = file:make_dir(Package),
        ok = erl_tar:extract({binary, Contents}, [compressed, {cwd, Package}]),
        {ok, slate_lock_nif, Beam} = compile:file(
            filename:join([Cwd, "src", "slate_lock_nif.erl"]), [binary]),
        {module, slate_lock_nif} = code:load_binary(slate_lock_nif, "loader", Beam),
        {ok, Target} = slate_lock_nif:target(),
        true = filelib:is_regular(filename:join([Package, "priv", "slate_lock",
                                                 Target, library(Target)])),
        lists:foreach(fun(Name) ->
            true = filelib:is_regular(filename:join([Package, "priv", "slate_lock",
                                                     "source", Name]))
        end, ["Cargo.toml", "Cargo.lock", "rust-toolchain.toml", "build.escript", "src/lib.rs"]),
        Consumer = filename:join(Root, "consumer"),
        Src = filename:join(Consumer, "src"),
        ok = filelib:ensure_dir(filename:join(Src, "placeholder")),
        Relative = "../package",
        ok = file:write_file(filename:join(Consumer, "gleam.toml"),
            ["name = \"exclusive_package_probe\"\nversion = \"0.0.0\"\ntarget = \"erlang\"\n",
             "[dependencies]\ngleam_stdlib = \">= 0.48.0 and < 2.0.0\"\n",
             "slate = { path = \"", Relative, "\" }\n"]),
        lists:foreach(fun(Name) ->
            {ok, _} = file:copy(filename:join([Cwd, "test", "support", "consumer", "src", Name]),
                               filename:join(Src, Name))
        end, ["exclusive_package_probe.gleam", "exclusive_package_probe_ffi.erl"]),
        run("gleam", ["run"], Consumer),
        run("gleam", ["export", "erlang-shipment"], Consumer),
        Shipment = filename:join([Consumer, "build", "erlang-shipment"]),
        Erl = os:find_executable("erl"),
        Paths = lists:append([["-pa", Ebin] || Ebin <- filelib:wildcard(
            filename:join([Shipment, "*", "ebin"]))]),
        run_executable(Erl, ["+S", "2:2", "+A", "1", "-noshell"] ++ Paths ++
            ["-eval", "'exclusive_package_probe@@main':run(exclusive_package_probe)."], Root),
        run("gleam", ["export", "escript"], Consumer),
        Relocated = filename:join(Root, "relocated"),
        Elsewhere = filename:join(Root, "elsewhere"),
        ok = file:make_dir(Relocated),
        ok = file:make_dir(Elsewhere),
        Script = filename:join(Relocated, "exclusive_package_probe"),
        {ok, _} = file:copy(filename:join(Consumer, "exclusive_package_probe"), Script),
        run_executable(os:find_executable("escript"), [Script, "missing"], Elsewhere),
        Native = filename:join([Relocated, "slate_native", Target]),
        ok = filelib:ensure_dir(filename:join(Native, "placeholder")),
        {ok, _} = file:copy(filename:join([Package, "priv", "slate_lock", Target, library(Target)]),
                           filename:join(Native, library(Target))),
        run_executable(os:find_executable("escript"), [Script], Elsewhere),
        io:format("Hex consumer, shipment, and relocated escript proofs passed.~n")
    after
        ok = file:del_dir_r(Root)
    end;
main(_) -> error("Usage: exclusive-package.escript [--release-artifacts]").

targets() -> ["x86_64-linux-gnu", "aarch64-linux-gnu", "x86_64-apple-darwin",
              "aarch64-apple-darwin", "x86_64-pc-windows"].
library("x86_64-pc-windows") -> "slate_lock.dll";
library(_) -> "slate_lock.so".

require_artifact(Target) ->
    Path = filename:join(["priv", "slate_lock", Target, library(Target)]),
    case filelib:is_regular(Path) andalso filelib:file_size(Path) > 0 of
        true -> ok;
        false -> error({missing_native_artifact, Path})
    end.

run(Name, Args, Directory) ->
    case os:find_executable(Name) of
        false -> error({missing_executable, Name});
        Executable -> run_executable(Executable, Args, Directory)
    end.

run_executable(Executable, Args, Directory) ->
    io:format("Running ~ts~n", [filename:basename(Executable)]),
    Missing = case lists:member("missing", Args) of true -> "true"; false -> "false" end,
    Port = open_port({spawn_executable, Executable},
                     [binary, exit_status, use_stdio, stderr_to_stdout,
                      {cd, Directory}, {args, Args},
                      {env, [{"ERL_FLAGS", "+S 2:2 +A 1"},
                             {"SLATE_PACKAGE_MISSING", Missing}]}]),
    wait(Port, erlang:monotonic_time(millisecond) + 180000).

wait(Port, Deadline) ->
    receive
        {Port, {data, Data}} -> io:put_chars(Data), wait(Port, Deadline);
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, Status}} -> error({command_failed, Status})
    after max(0, Deadline - erlang:monotonic_time(millisecond)) ->
        {os_pid, Pid} = erlang:port_info(Port, os_pid),
        kill_child(Pid),
        error(command_timeout)
    end.

kill_child(Pid) ->
    {Command, Args} = case os:type() of
        {win32, _} -> {"taskkill", ["/PID", integer_to_list(Pid), "/T", "/F"]};
        {unix, _} -> {"kill", ["-KILL", integer_to_list(Pid)]}
    end,
    Port = open_port({spawn_executable, os:find_executable(Command)},
                     [binary, exit_status, use_stdio, stderr_to_stdout, {args, Args}]),
    wait(Port, erlang:monotonic_time(millisecond) + 10000).
