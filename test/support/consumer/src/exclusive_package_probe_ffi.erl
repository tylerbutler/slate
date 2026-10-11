-module(exclusive_package_probe_ffi).
-export([missing_native/0, passed/0]).

missing_native() -> os:getenv("SLATE_PACKAGE_MISSING") =:= "true".
passed() -> io:format("SLATE native package probe passed~n"), nil.
