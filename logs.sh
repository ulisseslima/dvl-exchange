#!/bin/bash -e
# @installable
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $MYDIR/log.sh
[[ "$SETUP_DEBUG" == true ]] && debugging on
source $MYDIR/db.sh

echo $LOGF
less $LOGF
