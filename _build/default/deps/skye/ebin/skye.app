{application,skye,
    [{description,"massages..."},
     {vsn,"1.0.0"},
     {registered,[]},
     {applications,[kernel,stdlib,mnesia,lager,gproc]},
     {mod,{skye_app,[]}},
     {env,
         [{kall_nodes,['leon@pilot.skye.gem','chen@pilot.skye.gem']},
          {offer_node,'offer_agent@offer.lk.com'},
          {adapters,
              [{ctp,
                   [{program,"./ctp_market_cnode"},
                    {program_dir,"../adapters/bin/ctp/market/"},
                    {program_env,[{"LD_LIBRARY_PATH","../../../lib/ctp/"}]},
                    {relogin,[{freq,3000},{low_freq,60000},{max,60}]}]},
               {tap,
                   [{auth_key_dir,"./tap_auth/"},
                    {program,"./tap_market_cnode"},
                    {program_dir,"../adapters/bin/tap/market/"},
                    {program_env,[{"LD_LIBRARY_PATH","../../../lib/tap/"}]},
                    {log_dir,"log"},
                    {errors_in_file,"../adapters/include/tap/TapAPIError.h"},
                    {errors_out_file,"./tap_errors.data"},
                    {relogin,[{freq,3000},{low_freq,60000},{max,60}]}]},
               {cffex2,
                   [{schedule,
                        [{local,"Beijing"},
                         {weekday,[{{8,30,0},{15,30,0}}]},
                         {restart,{1000,3600,1}}]},
                    {comm_mode,port},
                    {program,"./cffex_market"},
                    {program_dir,"../adapters/bin/cffex/market/"},
                    {program_env,[{"LD_LIBRARY_PATH","../../../lib/cffex/"}]},
                    {log_dir,"log"}]},
               {ib,[{program,"java"},
                    {program_dir,undefined},
                    {program_args,
                        "-Xmx1024m -Xms1024m -D=../interactivebroker/logging.properties -classpath ../interactivebroker/lib/OtpErlang-1.5.10.jar:../interactivebroker/lib/args4j-2.32.jar:../interactivebroker/build/jar/IBGatewayClient.jar"},
                    {main_class,"com.blackbird.IBClientNode"},
                    {mbox,market},
                    {req_historical_data_interval,300}]}]}]},
     {modules,
         [application_util,demo,eagle_server,ib_connection,mnesia_lab,
          mnesia_util,node_context,proc,process_limit,query_util,skye,
          skye_app,skye_node_context,skye_storage,skye_sup,skye_util,
          soj_server]}]}.