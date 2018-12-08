-module(application_util).

-export([get_app_env/2]).

-export([start_supervisor/3,
         start_supervisor/4]).
-export([generic_supervisor/1,
         generic_supervisor/2,
         simple_supervisor/1]).
-export([supervisor_spec/3,
         external_supervisor_spec/1,
         external_supervisor_spec/2,
         simple_spec/2,
         module_spec/2,
         module_spec/3,
         children_spec/1,
         children_spec/2,
         children_spec/3,
         children_spec_with_protection/2,
         sup_children_spec/3]).

-export([memory_info/1, application_memory/1, applications_memory/0, ets_memory/0]).
-export([touch_node/2]).
-export([gen_server_call/2]).

-export([encode_record/2, decode_record/3]).
-export([encode_with_null/1]).
-define(MAXR, 1000).
-define(MAXT, 3600).

get_app_env(Opt, Default) ->
    App = case application:get_application() of
              undefined ->
                  [{Application, _, _} | _T] = application:which_applications(),
                  Application;
              {ok, Application} -> Application
          end,
    case application:get_env(App, Opt) of
        {ok, Val} -> Val;
        _ ->
            case init:get_argument(Opt) of
                {ok, [[Val | _]]} -> Val;
                error       -> Default
            end
    end.

start_supervisor(SupModule, Module, Args) ->
    supervisor:start_link({local, Module}, SupModule, [Module|Args]).
start_supervisor(SupModule, [Module|Ah], RegisterName, At) ->
    supervisor:start_link({local, RegisterName}, SupModule, [Module|Ah ++ At]).

generic_supervisor(Specs) ->
    generic_supervisor(Specs, one_for_one).
generic_supervisor(Specs, Type) when Type =:= one_for_one; Type =:= one_for_all ->
    {ok, {{Type, ?MAXR, ?MAXT}, Specs}}.

simple_supervisor(Spec) ->
    SupFlags = {simple_one_for_one, ?MAXR, ?MAXT},
    {ok, {SupFlags, [Spec]}}.

simple_spec(Module, Args) ->
    {Restart, Shutdown, Type} = {temporary, 2000, worker},
    {Module,
     {Module, start_link, Args},
     Restart, Shutdown, Type, [Module]}.

module_spec(Module, Args) ->
    {Restart, Shutdown, Type} = {transient, 2000, worker},
    {Module,
     {Module, start_link, Args},
     Restart, Shutdown, Type, [Module]}.

module_spec(Name, Module, Args) ->
    {Restart, Shutdown, Type} = {transient, 2000, worker},
    {Name,
     {Module, start_link, Args},
     Restart, Shutdown, Type, [Module]}.

supervisor_spec(SupModule, Module, Args) ->
    {Restart, Shutdown, Type} = {transient, infinity, supervisor},
    {Module,
     {?MODULE, start_supervisor, [SupModule, Module, Args]},
     Restart, Shutdown, Type ,[SupModule]}.

external_supervisor_spec(Module) ->
    external_supervisor_spec(Module, []).

external_supervisor_spec(Module, Args) ->
    {Restart, Shutdown, Type} = {transient, infinity, supervisor},
    {Module,
     {Module, start_link, Args},
     Restart, Shutdown, Type ,[Module]}.

children_spec(Module) ->
    children_spec(Module, []).

children_spec(Module, Args) ->
    children_spec(Module, Args, transient).

children_spec(Module, Args, RestartType) ->
    {Restart, Shutdown, Type} = {RestartType, 2000, worker},
    {undefined,
     {Module, start_link, Args},
     Restart, Shutdown, Type, [Module]}.

children_spec_with_protection(Module, Args) ->
    {Restart, Shutdown, Type} = {temporary, 2000, supervisor},
    {undefined,
     {supervisor_with_protection, start_link, [Module,Args]},
     Restart, Shutdown, Type, [Module]}.

sup_children_spec(SupModule, Module, Args) ->
    {Restart, Shutdown, Type} = {transient, infinity, supervisor},
    {undefined,
     {?MODULE, start_supervisor, [SupModule, [Module|Args]]},
     Restart, Shutdown, Type ,[Module]}.




%% Check the specific node exist or not, if the node is alive, return the pid,
%% otherwise start the node through [M, F, A]
touch_node(NodeName, [M, F, A]) ->
    case whereis(NodeName) of
        undefined -> apply(M, F, A);
        Node ->   Node
    end;

touch_node(NodeName, [F, A]) ->
    case whereis(NodeName) of
        undefined -> apply(F, A);
        Node ->  Node
    end.

gen_server_call(Server, Request) ->
    case catch gen_server:call(Server, Request) of
        {'EXIT', timeout, Reason} ->
            {error, timeout};
        {'EXIT', noproc, Reason} ->
            {error, noproc};
        {'EXIT', Reason} ->
            error_logger:error_msg("[~p] gen_server ~p self call failed ~p", [?MODULE, Server, Reason]),
            {error, invalid_gen_server};
        Else ->
            Else
    end.

encode_record(Data, Fields) ->
    encode_record(Data, Fields, []).

encode_record([], [], Props) ->
    {ok, lists:reverse(Props)};
encode_record(Data, [], Props) ->
    {error, invalid_prop};
encode_record([], Field, Props) ->
    {error, invalid_prop};
encode_record([Val|T], [Key|FT], Props) ->
    encode_record(T, FT, [{Key, Val}|Props]).

decode_record(Props, [], Result) ->
    {ok, list_to_tuple(lists:reverse(Result))};
decode_record(Props, [F|T], Result) ->
    Value = proplists:get_value(F, Props),
    decode_record(Props, T, [Value|Result]).

encode_with_null(undefined) ->
    null;
encode_with_null(Data) ->
    Data.

applications_memory() ->
    try application:which_applications() of
        Apps ->
            lists:map(
              fun({AppName, _, _}) ->
                      Mem = application_memory(AppName),
                      {AppName, Mem}
              end, Apps)
    catch
        _:Exception ->
            error_logger:error_msg("[~p] get application memory failed ~p", [?MODULE, Exception]),
            undefined
    end.

application_memory(App) ->
    case  application_controller:get_master(App) of
        Master when is_pid(Master) ->
            {Root, Name} = application_master:get_child(Master),
            {Memory, Children} = memory_info(Root),
            {Name, Memory div 1000000, Children};
        _ ->
            undefined
    end.

memory_info(Sup) ->
    Infos = supervisor:which_children(Sup),
    {M, E, ES} =
    lists:foldl(
      fun({Name, PId, Type, _}, {Total, Memories, MemorySets}) ->
              case Type of
                  worker ->
                      {memory, Memory} = process_info(PId, memory),
                      NTotal = Total + Memory,
                      case Name of
                          undefined ->
                              NMemorySets = 
                                  case gb_sets:size(MemorySets) of
                                      Size when Size > 10 ->
                                          {_, NSets} = 
                                              gb_sets:take_smallest(MemorySets),
                                          NSets;
                                      _ ->
                                          MemorySets
                                  end,
                              NNMemorySets = gb_sets:insert(
                                              {undefined, Memory, PId}, NMemorySets),
                              {NTotal, Memories, NNMemorySets};
                          Name ->
                                  {NTotal, [{Name, Memory, PId}|Memories], MemorySets}
                      end;
                  supervisor ->
                      {Memory, Each} = memory_info(PId),
                      NTotal = Total + Memory,

                      {NTotal, [{Name, {Memory, Each}, PId}|Memories], MemorySets}
              end
      end, {0, [], gb_sets:new()}, Infos),
    NE =
        case E of
            [] ->
                gb_sets:to_list(ES);
            _ ->
                E
        end,
    NNE = lists:map(
              fun({N, Mem, PId}) ->
                      case Mem of
                          Mem when is_integer(Mem) ->
                              {N, Mem div 1000000, undefined, PId};
                          {T, RestEach} ->
                              {N, T div 1000000, PId, RestEach}
                      end
              end, NE),
    NNNE = lists:reverse(lists:keysort(3, NNE)),
    {M, NNNE}.

ets_memory() ->
    All = ets:all(),
    AllMems = lists:map(
                fun(Ets) ->
                        Mem = ets:info(Ets, memory),
                        {Ets, Mem}
                end, All),
    Mems =
        lists:sort(
          fun({_, M1}, {_, M2}) ->
                  M1 > M2
          end, AllMems),
    Sum = lists:sum(lists:map(fun({_, Mem}) -> Mem end, AllMems)),
    {Sum, Mems}.
