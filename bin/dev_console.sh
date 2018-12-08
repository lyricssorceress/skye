#!/bin/bash
# -config app.config -config app.last.config \

#erl -pa ./ebin/ -boot start_sasl -pa deps/*/ebin -config app.config +P 3000000 -name chen@pilot.skye.gem -mnesia dir mnesia -s lager
#erl -pa ./ebin/ -boot start_sasl -pa deps/*/ebin -config app.config +P 3000000 -name leon@pilot.skye.gem -mnesia dir '"/Users/lc/lab/mnesia"' -s lager

erl -boot start_sasl -env ERL_LIBS _build/default/deps -config config/app.config +P 3000000 -name chen@pilot.skye.gem -mnesia dir mnesia -s lager -s mnesia -s skye

#erl -boot start_sasl -env ERL_LIBS _build/default/deps -config app.config +P 3000000 -name leon@pilot.skye.gem -mnesia dir '"/Users/lc/lab/mnesia"' -s mnesia
