-module(exclusive_test_logger).
-export([log/2]).

log(#{msg := {report, #{event := Event} = Report}}, #{config := #{owner := Owner}})
  when Event =:= slate_exclusive_cleanup_failed;
       Event =:= slate_exclusive_guardian_stopped ->
    Owner ! {captured_log, Report},
    ok;
log(_Event, _Config) -> ok.
