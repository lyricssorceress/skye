%%%-------------------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Oct 2018 22:04
%%%-------------------------------------------------------------------
-module(skye_storage).
-author("lc").

-include("node_tables.hrl").
%% API
-export([preload_tables/0, create_tables/0, init_schema/0, delete_tables/0]).

%% create schema
-spec(init_schema() -> ok | {error, Reason :: term()}).
init_schema() ->
  mnesia:create_schema([node()]).

-spec(create_tables() -> ok).
create_tables() ->
  {atomic, ok} = ?CREATE_TABLE(?CONTRACT),
  {atomic, ok} = ?CREATE_TABLE(?MARKET_HUB_INCREMENTER, ?INCREMENTER),
  ok.

-spec(delete_tables() -> {atomic, ok}).
delete_tables() ->
  {atomic, ok} = mnesia:delete_table(?CONTRACT).

-spec(preload_tables() -> {ok, ok} | {error, Tables :: list()}).
preload_tables() ->
  %mnesia_util:wait_for_tables([?CONTRACT, ?MARKET_HUB_INCREMENTER], 5000).
  ok.
