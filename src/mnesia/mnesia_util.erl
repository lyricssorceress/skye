%%%-------------------------------------------------------------------
%%% @author Jack Tang <jack@taodi.local>
%%% @copyright (C) 2010, Jack Tang
%%% @doc
%%%
%%% @end
%%% Created :  4 Aug 2010 by Jack Tang <jack@taodi.local>
%%%-------------------------------------------------------------------
-module(mnesia_util).

%% API
-export([]).
-compile(export_all).

%%%===================================================================
%%% API
%%%===================================================================

stopped_nodes() ->
    RunningNodes = mnesia:system_info(running_db_nodes),
    AllNodes = mnesia_lib:all_nodes(),
    AllNodes -- RunningNodes.

generate_query_condition(_Rec, Fields, Item) ->
    lists:foldl(
      fun(N, Acc) ->
              Key = lists:nth(N, Fields),
              Value = element(N + 1, Item),
              case Value of
                  undefined ->
                      Acc;
                  _ ->
                      [{Key, Value}|Acc]
              end
      end, [], lists:seq(1, length(Fields))).

show_index(Tab) ->
    Attrs = mnesia:table_info(Tab, attributes),
    IndexPos = mnesia:table_info(Tab, index),
    lists:foreach(fun(Pos) ->
                          IndexField = lists:nth(Pos, Attrs),
                          io:format("~p, ", [IndexField])
                  end, IndexPos).

restore(File, Table) when is_atom(Table) ->
    restore(File, [Table]);
restore(File, Tables) when is_list(Tables) ->
    AllTables  = mnesia:system_info(tables),
    
    lists:foreach(fun(Tab) ->
                          case mnesia:restore(File, [{skip_tables, AllTables -- [Tab] }]) of
                              {atomic, _} ->
                                  io:format("table ~p is restored~n", [Tab]);
                              _Error ->
                                  io:format("table can't be restored because ~p~n", [_Error])
                          end
                  end, Tables).

dump_to_textfile(File) ->
    dump_to_textfile(mnesia:system_info(is_running), file:open(File, write), all).
dump_to_textfile(File, Tabs) when is_list(Tabs)->
    dump_to_textfile(mnesia:system_info(is_running), file:open(File, write), Tabs).
dump_to_textfile(yes, {ok, F}, Tabs) ->
    Tabs1 = lists:delete(schema, mnesia:system_info(local_tables)),
    Tabs2 = lists:filter(
             fun(T) ->
                     case mnesia:table_info(T, storage_type) of
                         disc_copies -> true;
                         disc_only_copies -> true;
                         _ -> false
                     end
             end, Tabs1),
    DumpTabs = case Tabs of
                   all -> Tabs2;
                   _ when is_list(Tabs) ->
                       lists:filter(fun(T) ->
                                            lists:member(T, Tabs2)
                                    end, Tabs)
               end,
    io:format("dump tables ~p to file now~n", [DumpTabs]),
    Defs = lists:map(
             fun(T) -> {T, [{record_name, mnesia:table_info(T, record_name)},
                            {attributes, mnesia:table_info(T, attributes)}]} 
             end, DumpTabs),
    io:format(F, "~p.~n", [{tables, Defs}]),
    lists:foreach(fun(T) -> dump_tab(F, T) end, DumpTabs),
    file:close(F);
dump_to_textfile(_, {ok, F}, _Tabs) ->
    file:close(F),
    {error, mnesia_not_running};
dump_to_textfile(_, {error, Reason}, _Tabs) ->
    {error, Reason}.
    
dump_tab(F, T) ->
    W = mnesia:table_info(T, wild_pattern),
    {atomic,All} = mnesia:transaction(
		     fun() -> mnesia:match_object(T, W, read) end),
    lists:foreach(
      fun(Term) -> io:format(F,"~p.~n", [setelement(1, Term, T)]) end, All).

copy_table(Tab, NewTab) ->
    copy_nodes_table(Tab, NewTab, [node()]).

copy_nodes_table(Tab, NewTab, Nodes) ->
    F = fun() ->
                mnesia:foldl(
                  fun(Record, Acc) ->
                          mnesia:write(NewTab, Record, write),
                          Acc + 1
                  end, 0, Tab)
        end,
    case mnesia:create_table(
           NewTab, [{type, mnesia:table_info(Tab, type)},
                    {record_name, mnesia:table_info(Tab, record_name)},
                    {attributes, mnesia:table_info(Tab, attributes)},
                    {disc_copies, Nodes}]) of
        {atomic, ok} ->
            try mnesia:async_dirty(F) of
                Num ->
                    {atomic, Num}
            catch 
                _:Reason ->
                    {aborted, Reason}
            end;
        {aborted, Reason} ->
            {aborted, {create_new_table_failed, Reason}}
    end.

rename_table(Tab, NewTab) ->
    NewRec = mnesia:table_info(Tab, record_name),
    rename_table(Tab, NewTab, NewRec).
rename_table(Tab, NewTab, NewRec) ->
    Nodes = mnesia:table_info(Tab, disc_copies),
    NNodes = Nodes -- [node()],
    F = fun() ->
                mnesia:foldl(
                  fun(Record, Acc) ->
                          NRecord = setelement(1, Record, NewRec),
                          mnesia:write(NewTab, NRecord, write),
                          Acc + 1
                  end, 0, Tab)
        end,
    TabAttrs = mnesia:table_info(Tab, attributes),
    IndexOffs = mnesia:table_info(Tab, index),
    Indexes =
        lists:map(
          fun(Offset) ->
                  lists:nth(Offset - 1, TabAttrs)
          end, IndexOffs),
    case mnesia:create_table(
           NewTab, [{type, mnesia:table_info(Tab, type)},
                    {record_name, NewRec},
                    {attributes, mnesia:table_info(Tab, attributes)},
                    {disc_copies, Nodes}]) of
        {atomic, ok} ->
            try mnesia:async_dirty(F) of
                Num ->
                    lists:foreach(
                      fun(Index) ->
                              mnesia:add_table_index(NewTab, Index)
                      end, Indexes),
                    case del_table_copies(Tab, Nodes) of
                        {atomic, _} ->
                            lists:foreach(
                              fun(Node) ->
                                      mnesia:add_table_copy(Tab, Node, disc_copies)
                              end, NNodes),
                            {atomic, Num};
                        {aborted, R} ->
                            {aborted, R}
                    end
            catch 
                _:Reason ->
                    case del_table_copies(NewTab, Nodes) of
                        {atomic, _} ->
                            {aborted, Reason};
                        {aborted, R} ->
                            {aborted, {R, Reason}}
                    end
            end;
        {aborted, Reason} ->
            {aborted, {create_new_table_failed, Reason}}
    end.

create_table_from(Rec, Tab, FromTab, Attributes) ->
    TabAttrs = mnesia:table_info(FromTab, attributes),
    IndexOffs = mnesia:table_info(FromTab, index),
   case mnesia:table_info(FromTab, record_name) of
       Rec ->
           Indexes =
               lists:map(
                 fun(Offset) ->
                         lists:nth(Offset - 1, TabAttrs)
                 end, IndexOffs),
           case mnesia:create_table(Tab, [{type, mnesia:table_info(FromTab, type)},
                                          {record_name, Rec},
                                          {attributes, Attributes},
                                          {disc_copies, [node()]}]) of
               {atomic, ok} ->
                   RecAttrs = mnesia:table_info(Tab, attributes),
                   lists:foreach(
                     fun(Index) ->
                             case lists:member(Index, RecAttrs) of
                                 true ->
                                     mnesia:add_table_index(Tab, Index);
                                 false ->
                                     noop
                             end
                     end, Indexes),
                   {atomic, ok};
               {aborted, Reason} ->
                   {aborted, Reason}
           end;
       _ ->
           {aborted, rec_name_not_match}
   end.

del_table_copies(Tab, Nodes) ->
    lists:foldl(
      fun(Node, Acc) ->
              case Acc of
                  {aborted, Reason} ->
                      {aborted, Reason};
                  {atomic, Val} ->
                      case mnesia:del_table_copy(Tab, Node) of
                          {atomic, _} ->
                              {atomic, Val + 1};
                          {aborted, Reason} ->
                              {aborted, {del_table_failed, Node, Reason}}
                      end
              end
      end, {atomic, 0}, Nodes).


%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
replica_all_table(Contact, Verbose) ->
    {ok, _V} = mnesia:change_config(extra_db_nodes,[Contact]),
    case mnesia:change_table_copy_type(schema,Contact,disc_copies) of
        {atomic, ok} -> io:format("schema is transformed~n");
        Error -> io:format("Error when transforming schema: ~p~n", [Error])
    end,
            
    Tables = mnesia:system_info(tables) -- [schema],
    Result = lists:map(fun(T) ->
                {atomic, ok} = mnesia:add_table_copy(T,Contact,disc_copies),
                if Verbose ->
                        error_logger:info_msg("[~p]: -> copy table: ~p ~n", [?MODULE, T])
                end,
                ok
        end, Tables),
    {ok, Result}.

%%
%% Request = [{Tab1, disc_copies},
%%            {Tab2, ram_copies},
%%            {Tab3, disc_only_copies}]
replica_table(Contact, Request, Verbose) ->
    {ok, _V}     = mnesia:change_config(extra_db_nodes,[Contact]),
    case mnesia:change_table_copy_type(schema,Contact,disc_copies) of
        {atomic, ok} -> io:format("schema is transformed~n");
        Error -> io:format("Error when transforming schema: ~p~n", [Error])
    end,
    Tables       = mnesia:system_info(tables) -- [schema],
    Result       = lists:map(fun(T) ->
                case proplists:get_value(T, Request, null) of
                    null -> ignore; %% ignore the table
                    Type ->
                        {atomic, ok} = mnesia:add_table_copy(T, Contact, Type),
                        if Verbose ->
                                error_logger:info_msg("[~p] -> copy table: ~p ~n", [?MODULE, T])
                        end,
                        ok
                end
        end, Tables),
    {ok, Result}.

migrate_table(Rec, OldTable, Newtable, DefaultRec) ->
    F = fun(_, NData) -> {ok, NData} end,
    migrate_table(Rec, OldTable, Newtable, DefaultRec, F).

migrate_table(Rec, OldTable, NewTable, DefaultRec, Transformer) ->
    case query_util:find_all(OldTable, []) of
        {ok, Values} ->
            TabAttrs = mnesia:table_info(OldTable, attributes),
            RecAttrs = mnesia:table_info(NewTable, attributes),
            lists:foreach(
              fun(Data) ->
                      NRec = migrate_record(Data, Rec, TabAttrs, RecAttrs, DefaultRec),
                      case Transformer(Data, NRec) of
                          {ok, NData} ->
                              mnesia:dirty_write(NewTable, NData);
                          {error, Reason} ->
                              error_logger:error_msg("[~p] migrate record ~p failed ~p", [?MODULE, NRec,
                                                                                          Reason])
                      end
              end, Values),
            {ok, ok};
        {error, Reason} ->
            {error, Reason}
    end.

migrate_record(Data, Rec, TabAttrs, RecAttrs, DefaultRec) ->
    NewRec = lists:map(
               fun(N) ->
                       element(N + 1, DefaultRec)
               end, lists:seq(1, length(RecAttrs))),
    {_, NewData} = 
        lists:foldl(
          fun(TabAttr, {N, Middle}) ->
                  Result = 
                      lists:map(
                        fun(I) ->
                                RecAttr = lists:nth(I, RecAttrs),
                                case RecAttr =:= TabAttr of
                                    true ->
                                        element(N + 1, Data);
                                    false ->
                                        lists:nth(I, Middle)
                                end
                        end, lists:seq(1, length(RecAttrs))),
                  {N + 1, Result}
          end, {1, NewRec}, TabAttrs),
    list_to_tuple([Rec| NewData]).

update_schema(Tab, RecName, RecAttrs, DefaultRec) ->
    Transformer = fun(_, NRec) -> NRec end,
    update_schema(Tab, RecName, RecAttrs, DefaultRec, Transformer).

update_schema(Tab, Rec, RecAttrs, DefaultRec, Transformer) ->
    error_logger:info_msg("[~p] migrate table ~p started", [?MODULE, Tab]),
    TabAttrs = mnesia:table_info(Tab, attributes),
    IndexOffs = mnesia:table_info(Tab, index),
    Nodes = mnesia:table_info(Tab, disc_copies),
    NNodes = Nodes -- [node()],

    %% delete table copies of other nodes.
    lists:foreach(
      fun(Node) ->
              mnesia:del_table_copy(Tab, Node)
      end, NNodes),

    %% remove deprecated indexes.
    Indexes =
        lists:map(
          fun(Offset) ->
                  lists:nth(Offset - 1, TabAttrs)
          end, IndexOffs),
    lists:foreach(
      fun(Index) ->
              mnesia:del_table_index(Tab, Index)
      end, Indexes),
    F = fun(Data) ->
                NRec = migrate_record(Data, Rec, TabAttrs, RecAttrs, DefaultRec),
                Transformer(Data, NRec)
        end,
    Result = mnesia:transform_table(Tab, F, RecAttrs),
    lists:foreach(
      fun(Node) ->
              mnesia:add_table_copy(Tab, Node, disc_copies)
      end, NNodes),
    lists:foreach(
      fun(Index) ->
              case lists:member(Index, RecAttrs) of
                  true ->
                      mnesia:add_table_index(Tab, Index);
                  false ->
                      noop
              end
      end, Indexes),
    error_logger:info_msg("[~p] migrate table ~p finished", [?MODULE, Tab]),
    Result.

wait_for_tables(Tabs, Timeout) ->
    case mnesia:wait_for_tables(Tabs, Timeout) of
        ok -> {ok, ok};
        {timeout, BadTabList} ->
            error_logger:error_msg("[~p]: wait for tables ~p timeout after ~p ms, force load them~n",
                [?MODULE, BadTabList, Timeout]),
            Fails = lists:filter(fun(T) ->
                        case mnesia:force_load_table(T) of
                            yes -> false;
                            ErrorDesc ->
                                error_logger:error_msg("[~p]: force load ~p failed: ~p~n",
                                    [?MODULE, T, ErrorDesc]),
                                true
                        end
                end, BadTabList),
            {error, Fails};
        {error, Reason} ->
            error_logger:error_msg("[~p]: wait for tables ~p failed: ~p~n",
                [?MODULE, Reason]),
            {error, Tabs}
    end.
%%%===================================================================
%%% Internal functions
%%%===================================================================


%% On mypl@machine1
%mnesia:backup("/path/to/mnesia.backup").
%change_node_name(mnesia_backup, mypl@machine1, mypl@machine2,
%                 "/path/to/mnesia.backup", "/path/to/new.mnesia.backup").
%% On mypl@machine2
%mnesia:restore("/path/to/new.mnesia.backup", []).

change_node_name(Mod, From, To, Source, Target) ->
    Switch =
        fun(Node) when Node == From -> To;
           (Node) when Node == To -> throw({error, already_exists});
           (Node) -> Node
        end,
    Convert =
        fun({schema, db_nodes, Nodes}, Acc) ->
                {[{schema, db_nodes, lists:map(Switch,Nodes)}], Acc};
           ({schema, version, Version}, Acc) ->
                {[{schema, version, Version}], Acc};
           ({schema, cookie, Cookie}, Acc) ->
                {[{schema, cookie, Cookie}], Acc};
           ({schema, Tab, CreateList}, Acc) ->
                Keys = [ram_copies, disc_copies, disc_only_copies],
                OptSwitch =
                    fun({Key, Val}) ->
                            case lists:member(Key, Keys) of
                                true -> {Key, lists:map(Switch, Val)};
                                false-> {Key, Val}
                            end
                    end,
                {[{schema, Tab, lists:map(OptSwitch, CreateList)}], Acc};
           (Other, Acc) ->
                {[Other], Acc}
        end,
    mnesia:traverse_backup(Source, Mod, Target, Mod, Convert, switched).

