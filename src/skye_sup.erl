-module(skye_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_link/3, init/1]).

%% Supervisor callbacks


-include("ib.hrl").
-include_lib("windforce/include/windforce_application.hrl").


%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_link(Name, Child_Module, Args) ->
  supervisor:start_link({local, Name}, ?MODULE, [Child_Module, Args]).
%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
  Offer_Node = ?GET_APP_ENV(offer_node, []),
  Adapters = ?GET_APP_ENV(adapters, []),
  io:format("Adapters:~p~n~p~n~p~n", [Adapters, Offer_Node, Offer_Node]),
  Eagle_server = ?CHILD_SPEC_WORKER(?IB_EAGLE_SERVER, [skynet]),
  Mara_Sup = ?CHILD_SPEC_SUPERVISOR(?MODULE, ?IB_CONNECTION_SUPERVISOR, [?IB_CONNECTION, []]),
%%  Druid_Sup = ?CHILD_SPEC_SUPERVISOR(?MODULE, druid_adapter_tester, [eagle_server, [i1, i2]]),
  skye_storage:preload_tables(),
  Soj_Server = ?CHILD_SPEC_WORKER(?SOJ_SERVER, [test]), %% start_link(args1, args2)... [args1, args2].
  {ok, {?SUP_FLAGS_ONE_FOR_ONE, [Soj_Server, Mara_Sup]}};

init([Child_Module, Args]) ->
  io:format("Mara gets started:~p:~n", [Args]),
  {ok, {?SUP_FLAGS_SIMPLE_ONE_FOR_ONE, [?CHILD_SPEC_TEMP_WORKER(Child_Module, Args)]}}.



