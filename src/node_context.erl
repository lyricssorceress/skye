%%%-------------------------------------------------------------------
%%% @author Tiger Lee <tiger.lee@taodinet.com>
%%% @copyright (C) 2011, TaodiNet Ltd.
%%% @doc
%%%
%%% @end
%%% Created :  2011-07-04 by Tiger Lee <tiger.lee@taodinet.com>
%%%-------------------------------------------------------------------
-module(node_context).

-behaviour(gen_server).

%% API
-export([start_link/2, start_link/3]).
-export([channels/1,
         lookup_list/1,
         lookup/2,
         lookup/3,
         update/3,
         sync_update/3,
         increase/3,
         decrease/3,
         append/3,
         subtract/3,
         remove/3,
         counter/2,
         incr_counter/2,
         decr_counter/2,
         clear/2,
         subs/1,
         call/2,
         cast/2 ]).
-export([load_env/1]).

-export([behaviour_info/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).



-record(env, {name, value}).
-record(state, {retry_interval,        %% integer, N millseconds
                disconnected,          %% sets(), [{Module, Node}], disconnected broadcasters
                broadcaster_tab,       %% ets set, {ref(), {Module, Node}}, already subscribed broadcasters
                subscribers,           %% sets, [{Name, Node}],
                context,               %% ets, {Channel, MsgSource, ets}
                module,
                status,                %%
                pstate }).


%%%===================================================================
%%% API
%%%===================================================================
behaviour_info(callbacks) ->
    [
        {local_channel_context, 0},
        {init, 1},
        {sub_nodes, 1},
        {handle_update, 3},      %% handle_update(Channel, {Key, Value}, State)
        {handle_remove, 3},      %% handle_remove(Channel, {Key, Value}, State)
        {handle_save, 3},        %% handle_save(Channel, {Key, Value}, State)
        {handle_call, 3},
        {handle_cast, 2},
        {handle_call, 2}
    ].

call(Module, Msg) ->
    gen_server:call(Module, {call, Msg}).

cast(Module, Msg) ->
    gen_server:cast(Module, {cast, Msg}).

lookup(_Module, Channel) ->
    case ets:lookup(context, Channel) of
        [{Channel, _Source, KVTab}] -> KVTab;
        [] -> undefined
    end.

lookup_list(Channel) ->
    case ets:lookup(context, Channel) of
        [{Channel, _Source, KVTab}] -> ets:tab2list(KVTab);
        [] -> []
    end.

lookup(_Module, Channel, Key) ->
    case ets:lookup(context, Channel) of
        [{Channel, _Source, KVTab}] ->
            case ets:lookup(KVTab, Key) of
                [{Key, Value}] -> Value;
                [] -> undefined
            end;
        [] -> undefined
    end.

counter(Module, Key) ->
    lookup(Module, '_counter_', Key).

update(Module, Channel, {Key, Value}) ->
    gen_server:cast(Module, {update, Channel, {Key, Value}}).

sync_update(Module, Channel, {Key, Value}) ->
    gen_server:call(Module, {update, Channel, {Key, Value}}).

increase(Module, Channel, {Key, Step}) ->
    gen_server:cast(Module, {incr, Channel, {Key, Step}}).

decrease(Module, Channel, {Key, Step}) ->
    gen_server:cast(Module, {decr, Channel, {Key, Step}}).

append(Module, Channel, {Key, Step}) ->
    gen_server:cast(Module, {append, Channel, {Key, Step}}).

subtract(Module, Channel, {Key, Step}) ->
    gen_server:cast(Module, {subtract, Channel, {Key, Step}}).

incr_counter(Module, Key) ->
    gen_server:cast(Module, {incr, Key}).

decr_counter(Module, Key) ->
    gen_server:cast(Module, {decr, Key}).

channels(Module) ->
    gen_server:call(Module, channels).

remove(Module, Channel, Key) ->
    gen_server:cast(Module, {remove, Channel, Key}).

clear(Module, Channel) ->
    gen_server:cast(Module, {clear, Channel}).

subs(Module) ->
    gen_server:call(Module, subscribers).

load_env(Tab) ->
    case query_util:dirty_find_all(Tab, []) of
        {ok, Env} ->
            lists:map(fun(#env{name=K, value=V}) ->
                        {K, V}
                end, Env);
        {error, Reason} ->
            error_logger:error_msg("[~p] !!! load ~p failed: ~p~n",
                [?MODULE, Tab, Reason]),
            []
    end.

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Module, Args) ->
    start_link(Module, Args, 5000).
start_link(Module, Args, RetryInterval) when is_atom(Module) ->
    gen_server:start_link({local, Module}, ?MODULE, [Module, RetryInterval, Args], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initiates the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Module, RetryInterval, Args]) ->
    case Module:init(Args) of
        {ok, PS} ->
            D = sets:from_list(Module:sub_nodes(PS)),
            B = ets:new(broadcaster_tab, [named_table, set, protected]),
            S = sets:new(),

            C = ets:new(context, [named_table, set, protected]),
            load_local_context(Module, C),

            self() ! subscribe_node,

            {ok, #state{ retry_interval  = RetryInterval,
                         disconnected    = D,
                         broadcaster_tab = B,
                         subscribers     = S,
                         context         = C,
                         module          = Module,
                         pstate          = PS }};
        _ -> {ok, #state{}}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({call, Msg}, From, #state{module=M, pstate=PS}=State) ->
    case M:handle_call(Msg, From, PS) of
        {reply, Reply, NPS} ->
            {reply, Reply, State#state{pstate=NPS}};
        {noreply, NPS} ->
            {noreply, State#state{pstate=NPS}}
    end;

handle_call({update, Channel, {Key, Value} }, _From, State) ->
    NState = do_update(fun(_Tab) ->
                case Value of
                    _ when is_list(Value) ->
                        lists:usort(Value);
                    _ ->
                        Value
                end
        end, Channel, Key, State),
    {reply, {ok, ok}, NState};

handle_call(channels, _From, #state{context=C}=State) ->
    Reply = ets:foldl(fun({Channel, MsgSource, _KVTab}, Acc0) ->
                [{MsgSource, Channel} | Acc0]
        end, [], C),
    {reply, Reply, State};

handle_call(subscribers, _From, #state{subscribers=S}=State) ->
    {reply, sets:to_list(S), State};

handle_call({subscribe_context, ServerRef}, From, #state{context=C, subscribers=S}=State) ->
    NS = sets:add_element(ServerRef, S),
    error_logger:error_msg("[~p] got subscriber: ~p~n", [?MODULE, ServerRef]),
    Node = get_node(ServerRef),
    gen_server:reply(From, {ok, ok}),
    ets:foldl(fun({Channel, MsgSource, Tab}, _) ->
                case MsgSource =:= Node of
                    true -> ok;
                    false ->
                        ets:foldl(fun({Key, Value}, _) ->
                                    gen_server:cast(ServerRef, {handle_update, node(), MsgSource, Channel, {Key, Value}})
                            end, ok, Tab)
                end
        end, ok, C),
    {noreply, State#state{subscribers=NS}};

handle_call({unsubscribe_context, ServerRef}, _From, #state{subscribers = S} = State) ->
    NS = sets:del_element(ServerRef, S),
    {reply, {ok, ok}, State#state{subscribers=NS}};

handle_call(_Request, _From, State) ->
    error_logger:error_msg("[~p]: can't handle request ~p~n", [?MODULE, _Request]),
    {reply, {error, invalid_req}, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({cast, Msg}, #state{module = M, pstate = PS}=State) ->
    {noreply, NPS} = M:handle_cast(Msg, PS),
    {noreply, State#state{pstate=NPS}};

handle_cast({update, Channel, {Key, Value} }, State) ->
    NState = do_update(fun(_Tab) ->
                case Value of
                    _ when is_list(Value) ->
                        lists:usort(Value);
                    _ ->
                        Value
                end
        end, Channel, Key, State),
    {noreply, NState};

handle_cast({incr, Channel, {Key, Step} }, State) ->
    NState = do_update(fun(Tab) ->
                case ets:lookup(Tab, Key) of
                    [] ->
                        Step;
                    [{Key, Value}] when is_number(Value), is_number(Step) ->
                        Value + Step;
                    [{Key, Value}] ->
                        error_logger:warning_msg("[~p] ~p increase from ~p failed: invalid format ~p~n",
                            [?MODULE, Key, Value, Step]),
                        ignore
                end
        end, Channel, Key, State),
    {noreply, NState};

handle_cast({decr, Channel, {Key, Step} }, State) ->
    NState = do_update(fun(Tab) ->
                case ets:lookup(Tab, Key) of
                    [] when is_number(Step) ->
                        -Step;
                    [{Key, Value}] when is_number(Value), is_number(Step) ->
                        Value - Step;
                    [{Key, Value}] ->
                        error_logger:warning_msg("[~p] ~p decrease from ~p failed: invalid format ~p~n",
                            [?MODULE, Key, Value, Step]),
                        ignore
                end
        end, Channel, Key, State),
    {noreply, NState};

handle_cast({append, Channel, {Key, Step} }, State) ->
    NState = do_update(fun(Tab) ->
                case ets:lookup(Tab, Key) of
                    [] when is_list(Step) ->
                        lists:usort(Step);
                    [{Key, Value}] when is_list(Value), is_list(Step) ->
                        lists:usort(Value ++ Step);
                    [{Key, Value}] ->
                        error_logger:warning_msg("[~p] ~p append from ~p failed: invalid format ~p~n",
                            [?MODULE, Key, Value, Step]),
                        ignore
                end
        end, Channel, Key, State),
    {noreply, NState};

handle_cast({subtract, Channel, {Key, Step} }, State) ->
    NState = do_update(fun(Tab) ->
                case ets:lookup(Tab, Key) of
                    [] when is_list(Step) ->
                        [];
                    [{Key, Value}] when is_list(Value), is_list(Step) ->
                        Value -- Step;
                    [{Key, Value}] ->
                        error_logger:warning_msg("[~p] ~p subtract from ~p failed: invalid format ~p~n",
                            [?MODULE, Key, Value, Step]),
                        ignore
                end
        end, Channel, Key, State),
    {noreply, NState};

handle_cast({remove, Channel, Key}, State) ->
    NState = do_remove(Channel, Key, State),
    {noreply, NState};

handle_cast({clear, Channel}, #state{context=C}=State) ->
    NState = case ets:lookup(C, Channel) of
        [{Channel, _, KVTab}] ->
            lists:foldl(fun({Key, _Value}, Acc) ->
                        do_remove(Channel, Key, Acc)
                end, State, ets:tab2list(KVTab));
        [] ->
            State
    end,
    {noreply, NState};

handle_cast({incr, Key}, #state{context=C, subscribers = S}=State) ->
    [{'_counter_', _Source, CounterTab }] = ets:lookup(C, '_counter_'),
    NVal =
        case ets:lookup(CounterTab, Key) of
            [{Key, Val}] -> Val + 1;
            []           -> 1
        end,
    ets:insert(CounterTab, {Key, NVal} ),
    sets:fold(fun(ServerRef, _Acc) ->
                      gen_server:cast(ServerRef, {handle_update, node(), node(), '_counter_', {Key, NVal}})
              end, ok, S),
    {noreply, State};

handle_cast({decr, Key}, #state{context=C, subscribers = S}=State) ->
    [{'_counter_', _Source, CounterTab }] = ets:lookup(C, '_counter_'),
    NVal =
        case ets:lookup(CounterTab, Key) of
            [{Key, Val}] -> Val - 1;
            []           -> 0
        end,
    ets:insert(CounterTab, {Key, NVal} ),
    sets:fold(fun(ServerRef, _Acc) ->
                      gen_server:cast(ServerRef, {handle_update, node(), node(), '_counter_', {Key, NVal}})
              end, ok, S),
    {noreply, State};

handle_cast({handle_update, From, MsgSource, Channel, {Key, Value} }, #state{module = M, context=C,
                                                                             broadcaster_tab=B, subscribers=S,
                                                                             pstate = PS}=State) ->
    NState =
        case ets:match(B, {'$1', {'_', MsgSource}}) of
            [_Obj] when From =/= MsgSource ->
                State;
            _ ->
                case ets:lookup(C, Channel) of
                    [{Channel, _, KVTab }] ->
                        ets:insert(KVTab, {Key, Value});
                    [] ->
                        KVTab = ets:new(Channel, [set, protected]),
                        ets:insert(KVTab, {Key, Value}),
                        ets:insert(C, {Channel, MsgSource, KVTab})
                end,

                {noreply, NPS} = M:handle_update(Channel, {Key, Value}, PS),

                sets:fold(fun(ServerRef, _Acc) ->
                                  Node = get_node(ServerRef),
                                  case Node =:= MsgSource of
                                      true -> ok;
                                      false ->
                                          gen_server:cast(ServerRef, {handle_update, node(),
                                                                      MsgSource, Channel, {Key, Value} })
                                  end
                          end, [], S),
                State#state{pstate=NPS}
        end,
    {noreply, NState};

handle_cast({handle_remove, _From, MsgSource, Channel, {Key, Value} }, #state{module = M, context=C,
                                                                    subscribers=S, pstate = PS}=State) ->
    NState = case ets:lookup(C, Channel) of
        [{Channel, MsgSource, KVTab }] ->
            case ets:lookup(KVTab, Key) of
                [] -> State;
                [{Key, LocalValue}] ->
                    %% NOTE: 在上一个handle_update未收到的情况下，Value不一定与LocalValue相等
                    %%       所以此处以本地的Value为准
                    ets:delete(KVTab, Key),
                    {noreply, NPS} = M:handle_remove(Channel, {Key, LocalValue}, PS),

                    sets:fold(fun(ServerRef, _Acc) ->
                                      Node = get_node(ServerRef),
                                      case Node =:= MsgSource of
                                          true -> ok;
                                          false ->
                                              gen_server:cast(ServerRef, {handle_remove, node(),
                                                                          MsgSource, Channel, {Key, Value} })
                                      end
                              end, [], S),
                    State#state{pstate=NPS}
            end;
                 [] ->
            State
    end,
    {noreply, NState};

handle_cast(_Msg, State) ->
    error_logger:error_msg("[~p]: can't handle msg: ~p~n", [?MODULE, _Msg]),
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
handle_info(subscribe_node, #state{disconnected = D, retry_interval = R,
                                   broadcaster_tab = B} = State) ->
    ND = sets:filter(fun(ServerRef) ->
                do_subscribe(ServerRef, B)
        end, D),
    case sets:size(ND) of
        0 -> ok;
        _ ->
            case R of
                infinity -> ok;
                R  ->  timer:send_after(R, subscribe_node)
            end
    end,
    {noreply, State#state{disconnected = ND}};

handle_info({'DOWN', Ref, _Type, _Target, _Info}, #state{ broadcaster_tab = BroadcasterTab, context = C,
                                                          retry_interval = R, disconnected = D} = State) ->
    case ets:lookup(BroadcasterTab, Ref) of
        [{Ref, ServerRef}] ->
            Node = get_node(ServerRef),
            error_logger:error_msg("[~p] broadcaster ~p down~n", [?MODULE, ServerRef]),
            %% clear context from offline node.
            ets:foldl(fun({_Channel, MsgSource, Tab}, _Acc) ->
                        case Node =:= MsgSource of
                            true -> ets:delete_all_objects(Tab);
                            false -> ok
                        end
                end, ok, C),

            ets:delete(BroadcasterTab, Ref),
            ND = sets:add_element(ServerRef, D),
            case R of
                infinity -> ok;
                R -> timer:send_after(R, subscribe_node)
            end,
            {noreply, State#state{disconnected = ND}};
        [] ->
            {noreply, State}
    end;

handle_info(Info, #state{module=M, pstate=PS}=State) ->
    {noreply, NPS} = M:handle_info(Info, PS),
    {noreply, State#state{pstate=NPS}}.

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
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
load_local_context(Module, Context) ->
    % setup '_counter_' channel
    CounterTab = ets:new(counters, [set, protected]),
    ets:insert(Context, {'_counter_', node(), CounterTab}),
    case Module:local_channel_context() of
        {ok, Channels} when is_list(Channels) ->
            lists:foreach(
              fun({Channel, KVList}) ->
                      case KVList of
                          KVList when is_list(KVList) ->
                              KVTab = ets:new(Channel, [set, protected]),
                              lists:foreach(fun({Key, Value}) ->
                                                    ets:insert(KVTab, {Key, Value})
                                            end, KVList),
                              ets:insert(Context, {Channel, node(), KVTab });
                          KVTab ->
                              ets:insert(Context, {Channel, node(), KVTab })
                      end
              end, Channels);
        Other  -> Other
    end.

do_subscribe(ServerRef, BroadcasterTab) ->
    try gen_server:call(ServerRef, {subscribe_context, {process_name:by_pid(self()), node()}}) of
        {ok, ok} ->
            Ref = erlang:monitor(process, ServerRef),
            ets:insert(BroadcasterTab, {Ref, ServerRef}),
            error_logger:info_msg("[~p] subscribed context to node ~p ~n", [?MODULE, ServerRef]),
            false;
        Error ->
            error_logger:error_msg("[~p] subscribe context to ~p failed: ~p ~n", [?MODULE, ServerRef, Error]),
            true
        catch
            Error:_Exception ->
                error_logger:error_msg("[~p] subscribe context to ~p timeout: ~p ~n", [?MODULE, ServerRef, Error]),
                true
    end.

do_remove(Channel, Key, #state{module=M, context=C, subscribers=S, pstate=PS}=State) ->
    Node = node(),
    case ets:lookup(C, Channel) of
        [{Channel, Node, KVTab}] ->
            case ets:lookup(KVTab, Key) of
                [] -> State;
                [{Key, Value}] ->
                    ets:delete(KVTab, Key),
                    {noreply, NPS} = M:handle_remove(Channel, {Key, Value}, PS),
                    sets:fold(fun(ServerRef, _Acc) ->
                                gen_server:cast(ServerRef, {handle_remove, Node, Node, Channel, {Key, Value} })
                        end, ok, S),
                    State#state{pstate=NPS}
            end;
        [] ->
            State
    end.


get_node({_, Node}) ->
    Node;
get_node(ServerRef) ->
    node(ServerRef).

do_update(Fun, Channel, Key, #state{context=C, module=M, subscribers=S, pstate=PS}=State) ->
    Node = node(),
    case ets:lookup(C, Channel) of
        [{Channel, MsgSource, Tab}] when MsgSource =:= Node ->
            case Fun(Tab) of
                ignore ->
                    State;
                NewValue ->
                    ets:insert(Tab, {Key, NewValue}),
                    {noreply, PS1} = M:handle_update(Channel, {Key, NewValue}, PS),
                    {noreply, PS2} = M:handle_save(Channel, {Key, NewValue}, PS1),
                    sets:fold(fun(ServerRef, _Acc) ->
                                gen_server:cast(ServerRef, {handle_update, Node, Node, Channel, {Key, NewValue}})
                        end, ok, S),
                    State#state{pstate=PS2}
            end;
        [{Channel, MsgSource, _}] ->
            error_logger:error_msg("[~p] channel '~p' cann't be updated on this node, the source is ~p~n",
                [?MODULE, Channel, MsgSource]),
            State;
        [] ->
            error_logger:error_msg("[~p] channel '~p' cann't be updated on this node~n",
                [?MODULE, Channel]),
            State
    end.
