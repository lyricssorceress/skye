-define(
   PROP_TO_MATCH_HEAD(Keyvalpairs, Rec), 
   list_to_tuple([Rec|[query_util:value_of_field(Field, Keyvalpairs) || Field <- record_info(fields, Rec)]])).

-define(
   QUERY_TABLE(Tab, Prop, Cond, Result),
   MatchHead = ?PROP_TO_MATCH_HEAD(Prop, Tab),
   Guard = lists:map(fun(L) -> list_to_tuple(L) end, Cond),
   F = fun() -> mnesia:select(Tab, [{MatchHead, Guard, [Result]}]) end,
   % EmptyAtom = list_to_atom("no_such_" ++ atom_to_list(Tab)),
   case mnesia:transaction(F) of
      {aborted, Reason} -> {error, Reason};
      % {atomic, []} -> {error, EmptyAtom};
      {atomic, List} -> {ok, List}
   end).
