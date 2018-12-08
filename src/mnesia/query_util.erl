
-module(query_util).

-include("query_util.hrl").

-compile(export_all).

find_record(Tab, Id) ->
    F = fun() ->
                case mnesia:read(Tab, Id) of
                    [Data] ->
                        Data;
                    [] ->
                        mnesia:abort(no_such_rec)
                end
        end,
    mnesia:transaction(F).

find_in_tx(Tab, Query) ->
    Attributes = mnesia:table_info(Tab, attributes),
    case invalid_q(atomize_key(Query), Attributes) of
        [] ->
            MatchSpec = generate_match_spec(Tab, Query),
            mnesia:select(Tab, MatchSpec);
        InvalidFields ->
            mnesia:abort({invalid_fields, InvalidFields})
    end.

%% if there is an enclosed transaction.
find_all_no_tx(Tab, Query) ->
    MatchSpec = generate_match_spec(Tab, Query),
    List =  mnesia:select(Tab, MatchSpec),
    {ok, List}.

%% Query = [{MatchHead, [Guard], [Result]}]
find_all(Tab, Query) ->
    Attributes = mnesia:table_info(Tab, attributes),
    case invalid_q(atomize_key(Query), Attributes) of
        [] ->
            F = fun() ->
                        MatchSpec = generate_match_spec(Tab, Query),
                        mnesia:select(Tab, MatchSpec)
                end,
            case mnesia:transaction(F) of
                {aborted, Reason} ->  {error, Reason};
                {atomic, List}    ->  {ok, List}
            end;
        InvalidFields ->
            {error, {invalid_fields, InvalidFields}}
    end.

find_by_index(Tab, Value, Index) ->
    F = fun() ->
                mnesia:index_read(Tab, Value, Index)
        end,
    f:return(mnesia:transaction(F)).

find_by_id(Tab, Id) ->
    F = fun() ->
                case mnesia:read(Tab, Id) of
                    [] ->
                        mnesia:abort(no_rec);
                    [Record] ->
                        Record
                end
        end,
    f:return(mnesia:transaction(F)).

select(Tab, Query, Fields) ->
   Attributes = mnesia:table_info(Tab, attributes),
    case invalid_q(atomize_key(Query), Attributes) of
        [] ->
            MatchSpec = generate_match_spec(Tab, Query, Fields),
            F = fun() -> mnesia:select(Tab, MatchSpec) end,
            case mnesia:transaction(F) of
                {aborted, Reason} ->  {error, Reason};
                {atomic, List}    ->  {ok, List}
            end;
        InvalidFields ->
            {error, {invalid_fields, InvalidFields}}
    end.

dirty_select(Tab, Query, Fields) ->
   Attributes = mnesia:table_info(Tab, attributes),
    case invalid_q(atomize_key(Query), Attributes) of
        [] ->
            MatchSpec = generate_match_spec(Tab, Query, Fields),
            try mnesia:dirty_select(Tab, MatchSpec) of
                V -> {ok, V}
            catch
                _:Exception -> {error, Exception}
            end;
        InvalidFields ->
            {error, {invalid_fields, InvalidFields}}
    end.     

dirty_find_all(Tab, Query) ->
    Attributes = mnesia:table_info(Tab, attributes),
    case invalid_q(atomize_key(Query), Attributes) of
        [] ->
            MatchSpec = generate_match_spec(Tab, Query),
            try mnesia:dirty_select(Tab, MatchSpec) of
                V -> {ok, V}
            catch
                _:{aborted, Reason} ->
                    {error, Reason};
                _:Exception ->
                    {error, Exception}
            end;
        InvalidFields ->
            {error, {invalid_fields, InvalidFields}}
    end.

dirty_find_by_index(Tab, Key, Index) ->
    try mnesia:dirty_index_read(Tab, Key, Index) of
        V ->
            {ok, V}
    catch
        _:{aborted, Reason} ->
            {error, Reason};
        _:Exception ->
            {error, Exception}
    end.

dirty_find_by_id(Tab, Id) ->
    try mnesia:dirty_read(Tab, Id) of
        [] ->
            {error, no_rec};
        [Record] ->
          {ok, Record}
    catch
        _:{aborted, Reason} ->
            {error, Reason};
        _:Exception ->
            {error, Exception}
    end.

dirty_find(Tab, Query, Options) ->
    case limit(Tab, [{qry, Query}|atomize_key(Options)], async_dirty) of
        {ok, {_Count, Val}} ->
            {ok, Val};
        {error, Reason} ->
            {error, Reason}
    end.

find_one_no_tx(Tab, Query) ->
    Attributes = mnesia:table_info(Tab, attributes),
    case invalid_q(atomize_key(Query), Attributes) of
        [] ->
            MatchSpec = generate_match_spec(Tab, Query),
            case  mnesia:select(Tab, MatchSpec) of
                []    ->  {error, no_rec};
                [Rec] ->  {ok, Rec}; 
                _     ->  {error, many_recs}
            end;
        InvalidFields ->
            {error, {invalid_fields, InvalidFields}}
    end.

find_one(Tab, Query) ->
    Attributes = mnesia:table_info(Tab, attributes),
    case invalid_q(atomize_key(Query), Attributes) of
        [] ->
            F = fun() ->
                        MatchSpec = generate_match_spec(Tab, Query),
                        mnesia:select(Tab, MatchSpec)
                end,
            case mnesia:transaction(F) of
                {aborted, Reason} ->  {error, Reason};
                {atomic,  []    } ->  {error, no_rec};
                {atomic,  [Rec] } ->  {ok, Rec}; 
                {atomic,  _List  } ->  {error, many_recs}
            end;
        InvalidFields ->
            {error, {invalid_fields, InvalidFields}}
    end.

find_one(Tab, Query, dirty) ->
    Attributes = mnesia:table_info(Tab, attributes),
    case invalid_q(atomize_key(Query), Attributes) of
        [] ->
            MatchSpec = generate_match_spec(Tab, Query),
            case mnesia:dirty_select(Tab, MatchSpec) of
                [ ]    -> {error, no_rec};
                [Rec ] -> {ok, Rec};
                [_H | _T ] -> {error, many_recs};
                {aborted, Reason} -> {error, Reason}
            end;
        InvalidFields ->
            {error, {invalid_fields, InvalidFields}}
    end.

find(Tab, Query, Options) ->
    Attributes = mnesia:table_info(Tab, attributes),
    case invalid_q(atomize_key(Query), Attributes) of
        [] ->
            case limit(Tab, [{qry, Query}|atomize_key(Options)]) of
                {ok, {_Count, Val}} ->
                    {ok, Val};
                {error, Reason} ->
                    {error, Reason}
            end;
        InvalidFields ->
            {error, {invalid_fields, InvalidFields}}
    end.

generate_match_spec(Tab, Q) ->
    generate_match_spec(Tab, Q, []).
    
generate_match_spec(Tab, Q, Fields) ->
    Rec = mnesia:table_info(Tab, record_name),
    RecordInfo = mnesia:table_info(Tab, attributes),
    FilteredQ = filter_q(atomize_key(Q), RecordInfo),
    FilteredF = lists:filter(fun(Field) -> lists:member(Field, RecordInfo) end, Fields),
    {Prop, Cond} = parse_query(FilteredQ, FilteredF),
    MatchHead = list_to_tuple([Rec| lists:map( fun(R) -> value_of_field(R, Prop) end, RecordInfo)]),
    Guard = lists:map(fun({Opt, Key, Value}) -> {Opt, value_of_field(Key, Prop), wrap_val(Value)} end, Cond),
    Results = parse_results(FilteredF, Prop),
%%    io:format("Results: ~p~n~p~n~p~n", [Results, MatchHead, Guard]),
    [{MatchHead, Guard, Results}].

generate_match_spec2(Tab, Q) ->
    generate_match_spec2(Tab, Q, []).
    
generate_match_spec2(Tab, Q, Fields) ->
    Rec = mnesia:table_info(Tab, record_name),
    RecordInfo = mnesia:table_info(Tab, attributes),
    FilteredQ = filter_q(atomize_key(Q), RecordInfo),
    FilteredF = lists:filter(fun(Field) -> lists:member(Field, RecordInfo) end, Fields),
    {Prop, Cond} = parse_query(FilteredQ, FilteredF),
    MatchHead = list_to_tuple([Rec| lists:map( fun(R) -> value_of_field(R, Prop) end, RecordInfo)]),
    Guard = lists:map(fun({Opt, Key, Value}) -> {Opt, value_of_field(Key, Prop), wrap_val(Value)} end, Cond),
    Results = parse_results(FilteredF, Prop),
    [{MatchHead, Guard, Results}].

%% Q = [{"name", xxx}, {"value", [lower, upper]}]
%% return : [{name, xxx}, {value, [lower, upper]}]
atomize_key(Q) ->
    atomize_key(Q, []).
atomize_key([Item|L], Result) ->
    case Item of
        {Key, Val} ->
            case is_atom(Key) of
                true -> atomize_key(L, [Item|Result]);
                _ELSE ->
                    case is_list(Key) of
                        true ->
                            NewItem = {list_to_atom(Key), Val},
                            atomize_key(L, [NewItem|Result]);
                        _ELSE ->
                            void %% do nothing
                    end
            end;
        {Key, Opt, Val} ->
            case is_atom(Key) of
                true -> atomize_key(L, [Item|Result]);
                _ELSE ->
                    case is_list(Key) of
                        true ->
                            NewItem = {list_to_atom(Key), Opt, Val},
                            atomize_key(L, [NewItem|Result]);
                        _ELSE ->
                            void %% do nothing
                    end
            end
    end;
atomize_key([], Result) ->
    Result.

filter_q(Q, Fields) ->
    lists:filter(
      fun(Item) ->
              case Item of
                  {Name, _Val} ->
                      lists:member(Name, Fields);
                  {Name, _Opt, _Val} ->
                      lists:member(Name, Fields)
              end
      end, Q).

invalid_q(Q, Fields) ->
    lists:filter(
      fun(Item) ->
              case Item of
                  {Name, _Val} ->
                      not lists:member(Name, Fields);
                  {Name, _Opt, _Val} ->
                      not lists:member(Name, Fields)
              end
      end, Q).

drop_name(Name, Select) ->
    lists:delete(Name, Select).

generate_new_prop(Name, Prop, CurIdx) ->
    case lists:keyfind(Name, 1, Prop) of
        {Name, _TempVar} ->
            {Prop, CurIdx};
        false ->
            TempVar = list_to_atom("\$" ++ integer_to_list(CurIdx)),
            {[{Name, TempVar}|Prop], CurIdx + 1}
    end.

generate_equal_query(Name, Val, Select, Prop, Cond, CurIdx) ->
    case lists:member(Name, Select) of
        true ->
            {NProp, NCurIdx} = generate_new_prop(Name, Prop, CurIdx),
            NCond = [{'=:=', Name, Val}|Cond],
            {NProp, NCurIdx, NCond};
        false ->
            NProp = [{Name, Val}|Prop],
            {NProp, CurIdx, Cond}
    end.
            
%%
%% parse_query(Q) -> { Prop, Cond }
%% Query = [{"name", xxx}, {"value", [lower, upper]}]
%% Prop = [{name, xxx}, {value, '$1'}]
%% Cond = [['>', '$1', lower], ['<', '$1', upper]]
parse_query(Q) ->
    parse_query(Q, []).
parse_query(Q, Select) ->
    parse_query(atomize_key(Q), Select, [], [], 1).
parse_query([], [], Prop, Cond, _CurIdx) ->
    {Prop, Cond};
parse_query([], [Field|Rest], Prop, Cond, CurIdx) ->
    {NProp, NCurIdx} = generate_new_prop(Field, Prop, CurIdx),
    parse_query([], Rest, NProp, Cond, NCurIdx);
parse_query([Item|L], Select, Prop, Cond, CurIdx) ->
    case Item of
        {Name, Val} ->
            case Val of
                [Lower, Upper] ->
                    {NProp, NCurIdx} = generate_new_prop(Name, Prop, CurIdx),
                    NewCond = gen_cond(Name, Lower, Upper) ++ Cond,
                    parse_query(L, drop_name(Name, Select), NProp, NewCond, NCurIdx);
                {obj, V} ->
                    {NProp, NCurIdx, NCond} = generate_equal_query(Name, V, Select, Prop, Cond, CurIdx),
                    parse_query(L, drop_name(Name, Select), NProp, NCond, NCurIdx);
                _ ->
                    {NProp, NCurIdx, NCond} = generate_equal_query(Name, Val, Select, Prop, Cond, CurIdx),
                    parse_query(L, drop_name(Name, Select), NProp, NCond, NCurIdx)
            end;
        {Name, Opt, Val} ->
            {NProp, NCurIdx} = generate_new_prop(Name, Prop, CurIdx),
            parse_query(L, drop_name(Name, Select), NProp, [{Opt, Name, Val}|Cond], NCurIdx)
    end.

wrap_val(Val) when is_tuple(Val) ->
    {Val};
wrap_val(Val) ->
    Val.

parse_results(Fields, Props) ->
    Results =
        lists:map(
          fun(AttrName) ->
                  {AttrName, Val} = lists:keyfind(AttrName, 1, Props),
                  Val
        end, Fields),
    case Results of
        [] -> ['$_'];
        [V] -> [V];
        _ -> [Results]
    end.

%% gen_cond(VarName, Lower, Upper) ->
%% if is_number(Lower) and is_number(Upper) -> [{'>=', VarName, Lower}, {'=<', VarName, Upper}]
%% else if is_number(Lower) -> [{'>', VarName, Lower}]
%% else if is_number(Upper) -> [{'<', VarName, Upper}]
%% else -> []
gen_cond(VarName, undefined, Upper) ->
    [{'=<', VarName, Upper}];
gen_cond(VarName, Lower, undefined) ->
    [{'>=', VarName, Lower}];
gen_cond(VarName, Lower, Upper) ->
    [{'>=', VarName, Lower}, {'=<', VarName, Upper}].

value_of_field(Field, Keyvalpairs) ->
    case lists:keyfind(Field, 1,  Keyvalpairs) of
        {_Key, Val} ->
            Val;
        false ->
            '_'
    end.

first_field(Table) ->
    lists:nth(1, mnesia:table_info(Table, attributes)).

limit(Tab, Options) ->
    limit(Tab, Options, transaction).

limit(Tab, Options, Action) ->
    Number = proplists:get_value(limit, Options, 0),
    Order = proplists:get_value(order, Options, first_field(Tab)),
    Offset = proplists:get_value(offset, Options, 0),
    Sort = proplists:get_value(sort, Options, asc),
    Query = proplists:get_value(qry, Options, []),
    Filters = proplists:get_value(filters, Options, []),
    MatchSpec = proplists:get_value(match_spec, Options, generate_match_spec(Tab, Query)),
    limit(Tab, Order, Offset, Number, Sort, MatchSpec, Filters, Action).

limit(Tab, Field, Offset, Number, Order, MatchSpec, Filters, Action)
  when (is_atom(Field) or is_list(Field)), is_atom(Order)->
    F = fun() ->
                limit_in_tx(Tab, Field, Offset, Number, Order, MatchSpec, Filters)
        end,
    case Action of
        transaction ->
            case mnesia:transaction(F) of
                {atomic, Val} -> {ok, Val};
                {aborted, Reason} -> {error, Reason}
            end;
        async_dirty ->
            try mnesia:async_dirty(F) of
                Val ->
                    {ok, Val}
            catch
                _:{aborted, Reason} ->
                    {error, Reason};
                _:Exception ->
                    {error, Exception}
            end
    end;
limit(Tab, Field, Offset, Number, Order, MatchSpec, Filters, Action) ->
    limit(Tab, to_atom(Field), Offset, Number, to_atom(Order), MatchSpec, Filters, Action).

limit_in_tx(Tab, Options) ->
    Number = proplists:get_value(limit, Options, 0),
    Order = proplists:get_value(order, Options, first_field(Tab)),
    Offset = proplists:get_value(offset, Options, 0),
    Sort = proplists:get_value(sort, Options, asc),
    Query = proplists:get_value(qry, Options, []),
    Filters = proplists:get_value(filters, Options, []),
    MatchSpec = proplists:get_value(match_spec, Options, generate_match_spec(Tab, Query)),
    limit_in_tx(Tab, Order, Offset, Number, Sort, MatchSpec, Filters).

limit_in_tx(Tab, Field, Offset, Number, Order, MatchSpec, Filters)
  when (is_atom(Field) or is_list(Field)), is_atom(Order)->
    select(get_field_number(Tab, Field),
           Offset,
           Number,
           mnesia:select(Tab, MatchSpec, 10, read),
           gb_sets:empty(), 0, Order, Filters);

limit_in_tx(Tab, Field, Offset, Number, Order, MatchSpec, Filters) ->
    limit_in_tx(Tab, to_atom(Field), Offset, Number, to_atom(Order), MatchSpec, Filters).

get_offset([ Field | _ ], Field, N) -> N;
get_offset([ _ | T ], Field, N) ->
    get_offset (T, Field, N + 1);
get_offset([], Field, _) ->
    mnesia:abort({no_such_field, Field}).

get_field_number(Tab, Field) when is_atom(Field) ->
    get_offset(mnesia:table_info(Tab, attributes), Field, 2);
get_field_number(Tab, Fields) when is_list(Fields) ->
    lists:map(
      fun(Field) ->
              get_field_number(Tab, Field)
      end, Fields).

select(_FieldNumber, Offset, Number, '$end_of_table', Tree, Count, Order, _Filters) ->
    Candidates = case Order of
                     asc ->
                         [ Record || { _, Record } <- gb_sets:to_list (Tree) ];
                     _ ->
                         [ Record || { _, Record } <- lists:reverse(gb_sets:to_list (Tree)) ]
                 end,
    case Number of
        0 ->
            {Count, Candidates};
        _ ->
            { _, Rest } = collection_util:safe_split_list(Offset, Candidates),
            { Result, _ } = collection_util:safe_split_list(Number, Rest),
            {Count, Result}
    end;
select(FieldNumber, Offset, Number, { Results, Cont }, Tree, Count, Order, Filters) ->
    
    ResultsFiltered = filter(Results, Filters),
    NewTree =
        lists:foldl(fun (Record, AccTree) ->
                            Key = generate_field_key(FieldNumber, Record),
                            %Key = { element (FieldNumber, Record), Record },
                             gb_sets:add(Key, AccTree)
                     end,
                     Tree,
                     ResultsFiltered),
    PrunedTree =
    case Number of
        0 -> NewTree;
        _ -> prune_tree (NewTree, Offset + Number, Order)
    end,

    select(FieldNumber,
           Offset,
           Number,
           mnesia:select (Cont),
           PrunedTree, Count + length(Results), Order, Filters).

generate_field_key(FieldNumber, Record) when is_integer(FieldNumber) ->
    { element (FieldNumber, Record), Record };
generate_field_key(FieldNumbers, Record) when is_list(FieldNumbers) ->
    List = 
        lists:map(
          fun(FieldNumber) ->
                  element(FieldNumber, Record)
          end, FieldNumbers),
    {list_to_tuple(List), Record}.

filter(Results, [Filter|_T]) ->
    lists:filter(Filter, Results);
filter(Results, []) ->
    Results.
prune_tree(Tree, Max, Order) ->
    case gb_sets:size (Tree) > Max of
        true ->
            case Order of
                desc ->
                    {_ , NewTree} = gb_sets:take_smallest(Tree),
                    prune_tree (NewTree, Max, Order);
                _ ->
                    { _, NewTree} = gb_sets:take_largest (Tree),
                    prune_tree (NewTree, Max, Order)
            end;
        false ->
            Tree
    end.

to_atom(Target) when is_binary(Target) ->
    list_to_atom(binary_to_list(Target));
to_atom(Target) when is_list(Target) ->
    list_to_atom(Target);
to_atom(Target) ->
    Target.
