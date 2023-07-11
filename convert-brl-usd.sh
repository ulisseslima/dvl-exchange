#!/bin/bash -e
# @installable
# converts a BRL value to USD
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

brl="$1"
require -nx brl "amount in BRL"

if [[ $(nan.sh "$brl") == true ]]; then
    $query "select $brl"
fi

exchange=$($MYDIR/scoop-rate.sh USD -x BRL "$@" | jq -r .rates.BRL)
require exchange
info "rate: 1 USD = $exchange BRL"

$query "select round((($brl)/$exchange)::numeric, 2)"
