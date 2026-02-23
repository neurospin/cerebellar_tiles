#!/bin/bash

jobid="$1";
state=$(ccc_mstat "$jobid" | awk -v id=$jobid '$1 == id {print $10}');

if [ -z "$state" ]; then
	state=$(ccc_mstat -H "$jobid" | awk -v id=$jobid '$1 == id {print $9}')
fi

case "$state" in 
	COMPLETED)
		echo success
	;;
	FAILED)
		echo failed
	;;
	PEN|R00|R01)
		echo running
	;;
	*)
		echo failed
	;;
esac
