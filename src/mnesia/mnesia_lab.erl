%%%------------c-------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. Sep 2018 10:19
%%%-------------------------------------------------------------------
-module(mnesia_lab).
-author("lc").
-include_lib("stdlib/include/qlc.hrl").
-include_lib("windforce/include/windforce_application.hrl").
-include_lib("windforce/include/windforce_mnesia.hrl").
%% API
-export([init_db/0, add/1, remove/1, query/2, all_shop/0, add/3, alter_table/0, atomize_key/1, collect_keys/1]).

-define(NODE_LIST, ['leon@pilot.skye.gem', 'chen@pilot.skye.gem']).
%%-define(CREATE_TABLE(Table_Name, Node_List),
%%  mnesia:create_table(Table_Name, [{ram_copies, Node_List}, {type, set}, {attributes, record_info(fields, Table_Name)}])).

-record(shop, {item, quantity, cost}).
-record(cost, {name, price}).


alter_table() ->
  New_Attributes = record_info(fields, shop),
  F = fun(Data) -> Data end,
  mnesia:transform_table(shop, F, New_Attributes).

init_db() ->
%%  Node_List = ['leon@pilot.skye.gem', 'chen@pilot.skye.gem'],
  Node_List = skye_util:get_app_env(kall_nodes, []),
  mnesia:create_schema(Node_List),
  mnesia:start(),
  ?CREATE_TABLE(shop),
  ?CREATE_TABLE(cost).

add(Item, Quantity, Cost) ->
  Shop = #shop{item = Item, quantity = Quantity, cost = Cost},
  F = fun() ->
    mnesia:write(Shop)
      end,
  mnesia:transaction(F).

add(Shop) when is_record(Shop, shop) ->
  F = fun() ->
    mnesia:write(Shop)
      end,
  mnesia:transaction(F);
add(Cost) when is_record(Cost, cost) ->
  F = fun() ->
    mnesia:write(Cost)
      end,
  mnesia:transaction(F).

remove(Item) when is_record(Item, shop); is_record(Item, cost) ->
  ok.

%%  using '$$' in result, {atomic,[[green,13],[apple,12]]}
%%  using '$_" in result, result the wholeq record.
% query_util:find_all(shop, [{item, '>', ping}, {quantity, '>', 5}]).
query(shop, Name) when Name =:= all ->
  mnesia:transaction(fun() ->
    mnesia:select(shop, [{#shop{item = '$1', quantity = '$2', cost = '_'}, [{'=:=', '$1', apple}], [['$1', '$2']]}]) end);
query(shop, Name) ->
  mnesia:transaction(fun() -> mnesia:read(shop, Name, read) end);
query(cost, Name) when Name =:= all ->
  mnesia:transaction(fun() -> mnesia:select(cost, [#cost{_ = '_'}], []) end);
query(cost, Name) ->
  mnesia:transaction(fun() -> mnesia:read(cost, Name, read) end).


all_shop() ->
  F = fun() ->
    Q = qlc:q([X || X <- mnesia:table(shop)]),
    qlc:e(Q)
      end,
  mnesia:transaction(F).

%% Key_Value_Pair = [{"something", 123}, {"another", ">", 231}] to [{something, 123}, {another, >, 231}].
%%
%%
atomize_key(Arg_List) ->
  Result = lists:map(fun(Arg) ->
                      case Arg of
                        {Key, Value} when not is_atom(Key) ->
                          {list_to_atom(Key), Value};
                        {Key, Operand, Value} when not is_atom(Key) ->
                          {list_to_atom(Key), Operand, Value};
                        _Unknown ->
                          _Unknown
                      end
                     end, Arg_List),
  Result.

collect_keys(Arg_List) ->
  Result = lists:foldl(fun(Arg, AccIn) ->
    case Arg of
      {Key, _Value} when not is_atom(Key) ->
        [list_to_atom(Key) | AccIn];
      {Key, _Value} ->
        [Key | AccIn];
      {Key, _Opr, _Value} when not is_atom(Key) ->
        [list_to_atom(Key) | AccIn];
      {Key, _Opr, _Value} ->
        [Key | AccIn]
    end
                       end, [], Arg_List),
  Result.


