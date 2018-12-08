%%%-------------------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 27. Sep 2018 10:07
%%%-------------------------------------------------------------------
-module(skye_node_context).
-author("lc").

-behaviour(node_context).

%% API
-export([start_link/1, handle_save/3, handle_remove/3, handle_update/3, local_channel_context/0, sub_nodes/1, update/2, remove/2]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================

update(Channel, {Key, Value}) ->
  node_context:update(?MODULE, Channel, {Key, Value}).

remove(Channel, Key) ->
  node_context:remove(?MODULE, Channel, Key).



%% node_context callbacks
%%
-spec(sub_nodes(State :: #state{}) -> []).
sub_nodes(_State) ->
%%  [{leon_node_context, 'chen@pilot.skye.gem'}].
  [].
local_channel_context() ->
  lager:info("loading"),
  {ok, [
    {rommies, [{leon, 26}, {gennifer, 35}, {lisa, 21}]},
    {buildings, [{hospital, 4}, {classroom, 266}, {dormetory, 24}]},
    {key_pairs, [{name, <<"HIHI">>}, {loryy, "northing"}]},
    {steve, {steve, rogers}}
  ]}.

-spec(handle_update(Channel :: atom(), {Key :: atom(), Value :: term()},
    State :: #state{}) -> {noreply, State :: #state{}}).
handle_update(Channel, {Key, Value}, State) ->
  io:format("~p Channel updated: key: ~p, value: ~p, State: ~p~n", [Channel, Key, Value, State]),
  {noreply, State}.

-spec(handle_remove(Channel :: atom(), {Key :: atom(), Value :: term()}, State :: #state{})
      -> {noreply, State :: #state{}}).
handle_remove(Channel, {Key, Value}, State) ->
  io:format("~p Channel removed: key: ~p, value: ~p, State: ~p~n", [Channel, Key, Value, State]),
  {noreply, State}.

-spec(handle_save(Channel :: atom(), {Key :: atom(), Value :: term()}, State :: #state{})
      -> {noreply, State :: #state{}}).
handle_save(Channel, {Key, Value}, State) ->
  io:format("~p Channel saved: key: ~p, value: ~p, State: ~p~n", [Channel, Key, Value, State]),
  {noreply, State}.

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
init(_Args) ->
  {ok, #state{}}.


%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(Args :: term()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Args) ->
  node_context:start_link(?MODULE, Args).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================


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
handle_info(_Info, State) ->
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
terminate(_Reason, _State) ->
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
