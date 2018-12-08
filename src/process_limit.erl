%%%-------------------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Sep 2018 14:03
%%%-------------------------------------------------------------------
-module(process_limit).
-author("lc").

%% API
-export([max/1]).

max(N) ->
  Max = erlang:system_info(process_limit),
  io:format("Max Process Num:~p~n", [Max]),
  erlang:statistics(runtime),

  statistics(wall_clock),
  Pid_List = for(1, N, fun() -> spawn(fun() -> wait() end) end),

  {_, Time1} = statistics(wall_clock),
  lists:foreach(fun(Pid) -> Pid ! die end, Pid_List),
  io:format("total time:~p~n", [Time1 * 1000 / N]),
  ok.

for(N, N, F) -> [F()];
for(I, N, F) -> [F() | for(I + 1, N, F)].

wait() ->
  receive
    die ->
      void
  end.
