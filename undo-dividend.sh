#!/bin/bash -e
# @installable
# deletes the last product op, or the one you specify
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh

$MYDIR/undo.sh dividends $1