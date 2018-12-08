%%%-------------------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Oct 2018 16:54
%%% handle IB connection informations....
%%%-------------------------------------------------------------------
-module(ib_connection).
-author("lc").

-behaviour(gen_server).

%% API
-export([start_link/3, shutdown/1, sync_contract/2]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-include_lib("windforce/include/windforce_application.hrl").
-include("ib.hrl").
-include("node_tables.hrl").

-define(SERVER, ?MODULE).
-define(REQUEST_IB_CONTRACT_DETAIL, ib_contract_detail).
-define(IB_REQUEST_ID, ib_request_id).

-record(state, {pname, ib_node_master, ib_node, username}).

%%%===================================================================
%%% API ib_connection:sync_contract(<<"CL">>, <<"hgc620315">>).
%%%===================================================================
shutdown(IB_Username) ->
  gen_server:cast(?PROCESS_NAME(?MODULE, IB_Username), shutdown).

-spec(sync_contract(Contracts :: binary, IB_Username :: binary) -> ok).
sync_contract(Contract, IB_Username) ->
  gen_server:cast(?PROCESS_NAME(?MODULE, IB_Username), {?REQUEST_IB_CONTRACT_DETAIL, Contract}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(IB_Username :: binary, Password :: binary, Type :: live | paper) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(IB_Username, Password, Type) ->
  Process_Name = ?PROCESS_NAME(?MODULE, IB_Username),
  gen_server:start_link({local, Process_Name}, ?MODULE, [IB_Username, Password, Type], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([IB_Username, Password, Type]) ->
  {IB_Process, IB_Node} = {mara, 'pilot@pilot.skye.gem'},
  Process_Name = ?PROCESS_NAME(?MODULE, IB_Username),
  {IB_Process, IB_Node} ! {ib_account_logon, self(), [IB_Username, Password, Type, Process_Name]},
  {ok, #state{pname = Process_Name, ib_node_master = IB_Process, ib_node = IB_Node, username = IB_Username}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast({?REQUEST_IB_CONTRACT_DETAIL, Contract}, #state{pname = PName, ib_node = IB_Node} = State) when is_binary(Contract) ->
  ReqId = mnesia:dirty_update_counter(?MARKET_HUB_INCREMENTER, {?INCREMENTER, PName}, 1),
  {PName, IB_Node} ! {?REQUEST_IB_CONTRACT_DETAIL, ReqId, [Contract]},
  {noreply, State};
handle_cast(shutdown, State) ->
  {stop, normal, State};
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_info({ib_account_logon, Result}, State) ->
  case Result of
    success ->
      lager:info("logon succeeded!"),
      {noreply, State};
    Reason -> {stop, Reason, State}
  end;
handle_info({?REQUEST_IB_CONTRACT_DETAIL, _ReqId, Result}, State) when is_record(Result, contract) ->
  case skye_util:save_data(Result) of
    {?ATOMIC, _Result} -> _Result;
    {aborted, Reason} -> lager:error("failed to save record: [~p], reason:[~p]", [Result, Reason])
  end,
  {noreply, State};
handle_info(_Info, State) ->
  lager:info("received message: [~p]", [_Info]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, #state{ib_node = IB_Node, ib_node_master = Master, username = Username} = _State) ->
  lager:info("HIHIH~p", {Master, IB_Node}),
  {Master, IB_Node} ! {ib_account_logout, self(), [Username]},
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
