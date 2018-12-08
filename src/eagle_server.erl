%%%-------------------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. Sep 2018 21:45
%%%-------------------------------------------------------------------
-module(eagle_server).
-author("lc").

-behaviour(gen_server).

%% API
-export([start_link/1, start_link/2, reboot_ib_node/0, shut_down_ib_node/0, ib_logon/1, shut_down/0, test/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-include("ib.hrl").
-define(SERVER, ?MODULE).

-record(state, {port, ib_node}).

%%%===================================================================
%%% API
%%%===================================================================
reboot_ib_node() ->
  gen_server:cast(?SERVER, ib_node_reboot).

shut_down_ib_node() ->
  gen_server:cast(?SERVER, ib_node_shutdown).

ib_logon(Username) ->
  gen_server:cast(?SERVER, {ib_account_logon, Username}).

shut_down() ->
  gen_server:cast(?SERVER, shut_down).

test() ->
  gen_server:cast(?SERVER, test).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(Args :: term()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Args) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []).


start_link(Args, Fire) ->
  io:format("We have argument: ~p~n~p~n", [Args, Fire]),
  gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []).
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
init(_Args) ->
  process_flag(trap_exit, true),
  Port = erlang:open_port({spawn, "java -cp bin/ib_node/*:bin/ib_node/ib_wrapper-1.0-SNAPSHOT.jar com.skye.ib.IBNode mara pilot@pilot.skye.gem"},
    [binary, {line, 1000},
      stderr_to_stdout]),
  link(Port),
  IB_Node = {mara, 'pilot@pilot.skye.gem'},
  {ok, #state{port = Port, ib_node = IB_Node}}.

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
handle_cast(ib_node_reboot, #state{ib_node = IB_Node} = State) ->
  IB_Node ! {ib_node_reboot, self()},
  {noreply, State};

handle_cast(ib_node_shutdown, #state{ib_node = IB_Node} = State) ->
  IB_Node ! {ib_node_shutdown, self()},
  {noreply, State};

handle_cast({ib_account_logon, _Username}, #state{ib_node = IB_Node} = State) ->
  IB_Node ! {ib_account_logon, self(), [<<"hgc620315">>, "wzly123", live]},
  {noreply, State};

handle_cast(shut_down, #state{ib_node = _IB_Node} = State) ->
  {stop, normal, State};

handle_cast(test, State) ->
    lager:info("hi there"),
    [{_, Pid, _, _}] = supervisor:which_children(ib_connection_sup),
    supervisor:terminate_child(ib_connection_sup, Pid),

  {noreply, State};
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
handle_info(timeout, State) ->
  io:format("timeout:"),
  {noreply, State};

handle_info({Port, {data, {eol, Message}}}, #state{port = Port} = State) ->
  Result = case Message of
             <<"IB NODE FAILED!">> ->
               lager:error("IB_NODE_FAILED, check IB_NODE logs for detailed information."),
               {stop, ib_node_failed, State};
             <<"IB NODE ON!">> ->
               lager:info("IB NODE ON"),
               %% now login
               Result2 = supervisor:start_child(ib_connection_sup, [<<"hgc620315">>, <<"wzly123">>, <<"live">>]),
               lager:info("started: ~p", [Result2]),
               {noreply, State};
             _ ->
               lager:info("message received from ib_node: [~p]", [Message]),
               {noreply, State}
           end,
  Result;

handle_info({'EXIT', Port, Reason}, #state{port = Port} = State) ->
  lager:info("IB_NODE down, Reason:~p~n", [Reason]),
  {stop, node_down_abnormally, State};

handle_info(_Info, #state{port = Port} = State) ->
  io:format("f info:[~p]", [erlang:port_info(Port, os_pid)]),
  io:format(">>>>>~p[~p]~n", [Port, _Info]),
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
terminate(_Reason, #state{ib_node = IB_Node}) ->
  IB_Node ! {ib_node_shutdown, self()},
  skye_util:clear_supervisor_children(?IB_CONNECTION_SUPERVISOR),
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
