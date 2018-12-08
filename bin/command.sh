#!/usr/bin/env bash

#java -cp build/libs/* com.skye.SubProcess

#java -cp ~/IdeaProjects/ib_wrapper/build/libs/* com.skye.Test

IBCINI='bin/IBController/IBController.ini'
TWSCP=bin/ibgateway/*

java -cp  $TWSCP:bin/IBController/IBController.jar ibcontroller.IBGatewayController $IBCINI $1 $2 $3 $4
