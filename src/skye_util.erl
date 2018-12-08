%%%-------------------------------------------------------------------
%%% @author lc
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Oct 2018 19:46
%%%-------------------------------------------------------------------
-module(skye_util).
-author("lc").

%% API
-export([clear_supervisor_children/1, save_data/1, get_app_env/2, get_app_env2/2]).

clear_supervisor_children(Supervisor) ->
  Children = supervisor:which_children(Supervisor),
  lists:map(fun({_Id, Pid, _Type, _Modules}) ->
    supervisor:terminate_child(Supervisor, Pid),
    supervisor:delete_child(Supervisor, Pid)
            end, Children),
  ok.

-spec(save_data(Record :: term()) -> {aborted, Reason :: term()} | {atomic, Result :: term()}).
save_data(Record) when is_tuple(Record) ->
  Fun = fun() ->
    mnesia:write(Record)
        end,
  mnesia:transaction(Fun);
save_data(Record) ->
  {aborted, "not_supported: " ++ Record}.

%% {ok,[["hellofrom","ccc"]]}
get_app_env(Key, Default) ->
  Current_App = case application:get_application() of
                  undefined ->
                    [{App, _, _} | _] = application:which_applications(),
                    App;
                  {ok, App} -> App
                end,
  case application:get_env(Current_App, Key) of
    {ok, Value} -> Value;
    _ -> case init:get_argument(Key) of
           {ok, [[Value | _R] | _]} -> Value;
           _ -> Default
         end
  end.

get_app_env2(Opt, Default) ->
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
