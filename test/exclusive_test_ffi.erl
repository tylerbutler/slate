-module(exclusive_test_ffi).
-export([cleanup_sidecar/1]).

cleanup_sidecar(Path) ->
    {ok, Resolved} = slate_lock_nif:resolve(Path),
    Filename = unicode:characters_to_list(Resolved),
    case file:delete(Filename ++ ".slate.lock") of
        ok -> nil;
        {error, enoent} -> nil;
        {error, Reason} -> error({sidecar_cleanup_failed, Reason})
    end.
