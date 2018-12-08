%%%-------------------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 22. Sep 2018 16:26
%%%-------------------------------------------------------------------
-module(proc).
-author("lc").

%% API
-export([]).
-compile(export_all).

wait_hello() ->
  timer:send_after(10000, hello),
  receive
    hello -> throw(over)
  end.

wait_there() ->
  receive
    there -> exit(done)
  end.

start_hello() ->
  spawn(proc, wait_hello, []).

start_there() ->
  spawn(proc, wait_there, []).

async_start() ->
  spawn(fun() ->
    statistics(wall_clock),
    register(pilot, spawn_link(proc, wait_hello, [])),
    process_flag(trap_exit, true),
    receive
      {'EXIT', Pid, Why} ->
        {_, Time1} = statistics(wall_clock),
        io:format("result:~p~n, Reson:~p~n, Time elapsed:~p~n", [Pid, Why, Time1 * 1000])
    end
        end).

monitor_start() ->

  ok.

%% practise 1.
my_spawn(Mod, Func, Args) ->
  spawn(fun() ->
    {Pid, Ref} = spawn_monitor(Mod, Func, Args),
    statistics(wall_clock),
    receive
      {'DOWN', Ref, process, Pid, Why} ->
        {_, Time1} = statistics(wall_clock),
        io:format("[~p] terminated, reason: ~p~n, Time elapsed:~p~n", [Pid, Why, Time1])
    end
        end).

start_worker() ->
  register(rsepeator, Pid = spawn(proc, repeated_work, [])),
  Pid.

repeated_work() ->
  io:format("i am still working.~n"),
  receive
    kill ->
      exit(kill)
  after 5000 ->
    void
  end,
  repeated_work().

start_monitor(Pid) when is_pid(Pid) ->
  spawn(fun() ->
    Ref = monitor(process, Pid),
    Node = node(),
    receive
      {'DOWN', Ref, process, {Pid, Node}, Why} ->
        io:format("node down:~p, reason:~p", [Pid, Why]),
        NPid = start_worker(),
        start_monitor(NPid);
      Any ->
        io:format("Result: ~p", [Any])
    end
        end).

worker(N) ->
  io:format("[~p] [~p] started.~n", [self(), N]),
  receive
  after N * 1000 ->
    throw(a)
  end.

one_on_one() ->
  spawn(fun() ->
    process_flag(trap_exit, true),
    Result = [{spawn_link(proc, worker, [X]), {proc, worker, X}} || X <- lists:seq(1, 3)],
    io:format("Result:~p~n", [Result]),
    wait_result(Result)
        end).

wait_result(Result) ->
  receive
    {'EXIT', Pid, _Why} ->
      case lists:keyfind(Pid, 1, Result) of
        {Pid, {Module, Fun, Args}} = Item ->
          io:format("[~p] [~p] ended~n", [Pid, Args]),
          NResult = [{spawn_link(Module, Fun, [Args]), {Module, worker, Args}} | lists:delete(Item, Result)],
          wait_result(NResult);
        false ->
          io:format("no Pid: [~p] found.", [Pid]),
          wait_result(Result)
      end;
    Any ->
      io:format("receive any:~p~n", [Any])
  end.

wait_one_on_rest_result(Result) ->
  receive
    {'EXIT', Pid, _Why} ->
      case lists:keyfind(Pid, 1, Result) of
        {Pid, {Module, Fun, Args}} = Item ->
          io:format("[~p] [~p] ended~n", [Pid, Args]),
          NResult = [{spawn_link(Module, Fun, [Args]), {Module, worker, Args}} | lists:delete(Item, Result)],
          wait_result(NResult);
        false ->
          io:format("no Pid: [~p] found.", [Pid]),
          wait_result(Result)
      end;
    Any ->
      io:format("receive any:~p~n", [Any])
  end.

one_on_rest() ->
  and_you.

