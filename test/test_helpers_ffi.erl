-module(test_helpers_ffi).
-export([identity/1]).

%% Unsafe identity function used by test_helpers.unsafe_decoder/0
%% to bypass type checking in tests with complex value types.
identity(X) -> X.
