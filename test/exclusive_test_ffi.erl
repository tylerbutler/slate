-module(exclusive_test_ffi).
-export([cleanup_sidecar/1]).

cleanup_sidecar(Path) ->
    {ok, Resolved} = slate_lock_nif:resolve(Path),
    case file:delete(binary_to_list(Resolved) ++ ".slate.lock") of
        ok -> nil;
        {error, enoent} -> nil;
        {error, Reason} -> error({sidecar_cleanup_failed, Reason})
    end.
