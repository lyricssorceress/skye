#!/usr/bin/env bash
#TWSUSERID=zjhcxx170
#TWSPASSWORD=zjhcxx1701
#TWSAPIPORT=4001
#TRADINGMODE=paper

TWSDIR=~/Jts/ibgateway/963/jars/
JAVA_BIN=~/.i4j_jres/1.8.0_60_64/bin/java
TWSCP=$TWSDIR/jts4launch-963.jar:$TWSDIR/locales.jar:$TWSDIR/log4j-api-2.5.jar:$TWSDIR/log4j-core-2.5.jar:$TWSDIR/total-2015c.jar:$TWSDIR/twslaunch-963.jar:$TWSDIR/twslaunch-install4j-1.8.jar
IBCINI='./IBController.ini'
JAVAOPTS='-Xmx768M -XX:MaxPermSize=256M'

#java -cp  $TWSCP:./IBController.jar $JAVAOPTS ibcontroller.IBGatewayController $IBCINI $TWSUSERID $TWSPASSWORD $TWSAPIPORT $IBCTRLPORT $TRADINGMODE
$JAVA_BIN -cp  $TWSCP:./IBController-3.3.0-ibg-b963.jar $JAVAOPTS ibcontroller.IBGatewayController $IBCINI $1 $2 $3 $4 && echo $! > run.pid

