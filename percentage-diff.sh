#!/bin/bash -e
# @installable
# returns the diff in % between two values
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

value_a="$1"
value_b="$2"

require -nx value_a "value A"
require -nx value_b "value B"

$MYDIR/psql.sh "select percentage_diff($value_a, $value_b)"
