#!/bin/sh /etc/rc.common
. /usr/share/libubox/jshn.sh
. /lib/functions.sh

USE_PROCD=1

stop_service(){
	echo "stop"
}

start_service(){
	echo "start"	
}
