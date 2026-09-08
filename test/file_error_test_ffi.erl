-module(file_error_test_ffi).
-export([absolute_path/1, file_errors/1, pathless_errors/0, unknown_error/0, rename_error/0]).

absolute_path(Path) ->
    list_to_binary(filename:absname(binary_to_list(Path))).

%% Exercise known OTP envelopes, including shapes that are difficult to
%% reproduce on disk (permissions under root and the 2 GB allocator limit).
file_errors(Path) ->
    Cases = [
        {{file_error, Path, enoent}, <<"file_not_found">>, <<"enoent">>},
        {{error, {file_error, binary_to_list(Path), {error, enoent}}},
            <<"file_not_found">>, <<"{error,enoent}">>},
        {{file_error, Path, eacces}, <<"access_denied">>, <<"eacces">>},
        {{file_error, Path, {error, eacces}}, <<"access_denied">>, <<"{error,eacces}">>},
        {{error, {file_error, Path, {error, {error, eacces}}}},
            <<"access_denied">>, <<"{error,{error,eacces}}">>},
        {{{file_error, Path, {error, eacces}}, []},
            <<"access_denied">>, <<"{error,eacces}">>},
        {{file_error, Path, {error, einval}}, <<"access_denied">>, <<"{error,einval}">>},
        {{access_mode, Path}, <<"access_denied">>, <<"access_mode">>},
        {{type_mismatch, Path}, <<"type_mismatch">>, <<"type_mismatch">>},
        {{incompatible_arguments, Path}, <<"already_open">>, <<"incompatible_arguments">>},
        {{error, {incompatible_arguments, binary_to_list(Path)}},
            <<"already_open">>, <<"incompatible_arguments">>},
        {{error, {keypos_mismatch, Path}}, <<"type_mismatch">>, <<"keypos_mismatch">>},
        {{error, {needs_repair, Path}}, <<"needs_repair">>, <<"needs_repair">>},
        {{not_a_dets_file, Path}, <<"not_a_dets_file">>, <<"not_a_dets_file">>},
        {{file_error, Path, efbig}, <<"file_size_limit_exceeded">>, <<"efbig">>},
        {{file_error, Path, {error, efbig}},
            <<"file_size_limit_exceeded">>, <<"{error,efbig}">>},
        {{error, {no_more_space_on_file, Path}},
            <<"file_size_limit_exceeded">>, <<"no_more_space_on_file">>}
    ],
    [{slate_dets_ffi:translate_error(Reason), Code, Detail} || {Reason, Code, Detail} <- Cases].

pathless_errors() ->
    [slate_dets_ffi:translate_error(Reason) || Reason <- [
        not_a_dets_file, {error, needs_repair}, {file_error, undefined, eacces},
        {error, incompatible_arguments},
        {incompatible_arguments, slate_context_table},
        badarg, {no_such_table, slate_context_missing_table}
    ]].

unknown_error() ->
    slate_dets_ffi:translate_error({file_error, <<"private.dets">>, {error, enospc}}).

rename_error() ->
    slate_dets_ffi:translate_error({file_error, {"old.dets", "new.dets"}, eacces}).
