#!/bin/bash -e
# @installable
# deletes the last earning op, or the one you specify
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV

$MYDIR/undo.sh earnings $1
