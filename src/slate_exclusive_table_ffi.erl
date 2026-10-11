-module(slate_exclusive_table_ffi).
-export([table_filename/1, table_pid/1, still_open/2, lock_error_detail/1,
         exit_detail/1, log_guardian_stopped/2, log_owner_cleanup/3,
         log_undelivered/3, log_exception_cleanup/3]).

%% DETS has no typed Gleam inspection API. Keep filename encoding and tagged
%% handle inspection at this boundary; ownership and ordering live in Gleam.
table_filename(Table) ->
    case dets:info(Table, filename) of
        undefined -> {error, nil};
        Filename ->
            case unicode:characters_to_binary(Filename) of
                Binary when is_binary(Binary) -> {ok, Binary};
                Other -> error({exclusive_table_filename_invalid, Other})
            end
    end.

table_pid(Table) ->
    %% Missing/crashed DETS is a process failure, not a forged Pid.
    case dets:info(slate_dets_ffi:table_name(Table), pid) of
        Pid when is_pid(Pid) -> Pid;
        Other -> error({exclusive_table_pid_unavailable, Other})
    end.

still_open(Table, Pid) ->
    dets:info(slate_dets_ffi:table_name(Table), pid) =:= Pid.

lock_error_detail(Error) -> detail(Error).

exit_detail(Reason) -> detail(raw_exit(Reason)).

raw_exit(normal) -> normal;
raw_exit(killed) -> killed;
raw_exit({abnormal, Reason}) -> Reason.

log_guardian_stopped(Path, Reason) ->
    logger:error(#{event => slate_exclusive_guardian_stopped,
                   path => Path, reason => raw_exit(Reason)}),
    nil.

log_owner_cleanup(Path, Failures, Reason) ->
    logger:error(#{event => slate_exclusive_cleanup_failed,
                   path => Path, owner_exit => raw_exit(Reason), failures => Failures}),
    nil.

log_undelivered(Path, Error, Reason) ->
    logger:error(#{event => slate_exclusive_cleanup_failed,
                   path => Path, owner_exit => raw_exit(Reason), error => Error}),
    nil.

log_exception_cleanup(Path, Error, {Class, Reason}) ->
    logger:error(#{event => slate_exclusive_cleanup_failed,
                   path => Path, exception_class => Class, exception_reason => Reason,
                   error => Error}),
    nil.

detail(Reason) -> unicode:characters_to_binary(io_lib:format("~tp", [Reason])).
