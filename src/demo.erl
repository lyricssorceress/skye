%%%-------------------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Sep 2018 11:30
%%%-------------------------------------------------------------------
-module(demo).
-author("lc").

%% API
-export([test/0, by_pid/1, demo/0, start/0, deliver/1, grab_port/1, async_grab_port/1]).

test() ->
  uuid:uuid1(),
  uuid:uuid4().

demo() ->
  receive
    Any ->
      io:format(">>>[~p~n]", [Any])
  after infinity ->
    void
  end.

start() ->
  register(fire, spawn(demo, demo, [])).

by_pid(PId) when is_pid(PId) ->
  case lists:keyfind(registered_name, 1, process_info(PId)) of
    {_, Value} -> Value;
    false -> undefined
  end;
by_pid(_PId) ->
  undefined.

deliver(Message) ->
  {mara, 'pilot@pilot.skye.gem'} ! Message.

async_grab_port(Port) ->
  spawn(demo, grab_port, [Port]).

grab_port(Port) ->
  {ok, Listen} = gen_tcp:listen(Port, []),
  {ok, Socket} = gen_tcp:accept(Listen),
  loop(Socket),
  gen_tcp:close(Listen),
  gen_tcp:close(Socket).

loop(_Socket) ->
  receive
    Any ->
      Any
  end,
  loop(_Socket).