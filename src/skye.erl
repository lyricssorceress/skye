-module(skye).

%% Application callbacks
-export([start/0, stop/0]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start() ->
    ok = application:ensure_started(gproc),
    application:start(skye).

stop() ->
    application:stop(skye).
