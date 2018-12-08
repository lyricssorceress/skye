%%%-------------------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Oct 2018 14:34
%%%-------------------------------------------------------------------
-author("lc").

-define(IB_EAGLE_SERVER, eagle_server).
-define(SOJ_SERVER, soj_server).
-define(IB_CONNECTION_SUPERVISOR, ib_connection_sup).
-define(IB_CONNECTION, ib_connection).

%% issue No.: 9201
-record(contract_detail, {
  con_id,
  symbol,
  sec_type,
  last_trade_date,
  multiplier,
  exchange,
  currency,
  local_symbol,
  trading_class,
  market_name,
  min_tick,
  price_magnifier,
  order_types,
  valid_exchanges,
  long_name,
  contract_month,
  time_zone_id,
  trading_hours,
  liquid_hours
}).