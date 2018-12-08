%%%-------------------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Oct 2018 14:34
%%%-------------------------------------------------------------------
-author("lc").

-define(ATOMIC, atomic).
-define(ERROR, error).

%% Record Macros
-define(INCREMENTER, incrementer).


-define(CONTRACT, contract).
-define(MARKET_HUB_INCREMENTER, market_hub_incr).

-define(CREATE_TABLE(Table, Record, Storage, NodeList, Type, IndexList), mnesia:create_table(Table, [{Storage, NodeList}, {attributes, record_info(fields, Record)}, {type, Type}, {index, IndexList}])).
-define(CREATE_TABLE(Table, Record), ?CREATE_TABLE(Table, Record, disc_copies, [node()], set, [])).
-define(CREATE_TABLE(Table), ?CREATE_TABLE(Table, Table, disc_copies, [node()], set, [])).
-define(CREATE_TABLE_WITH_INDEX(Table, IndexList), ?CREATE_TABLE(Table, Table, disc_copies, [node()], set, IndexList)).


-record(incrementer, {key, id}).
-record(contract, {con_id, symbol, sec_type, last_trading_date, multiplier, exchange, currency, local_symbol, trading_class, market_name, min_tick,
  price_magnifier, order_types, valid_exchanges, long_name, contract_month, time_zone_id, trading_hours, liquid_hours}).
-record(rt_market, {local_symbol, con_id, symbol}).


