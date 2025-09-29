#!/bin/bash -e
# @installable
# converts a BRL value to USD
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

trap 'catch $? $LINENO' ERR
catch() {
  if [[ "$1" != "0" ]]; then
    >&2 echo "$ME - // returned $1 at line $2: $result"
  fi
}

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

usd="$1"
require -nx usd "amount in USD"
shift

if [[ $(nan.sh "$usd") == true ]]; then
    $query "select $usd"
fi

result=$($MYDIR/scoop-rate.sh USD -x BRL "$@")
exchange=$(echo "$result" | jq -r .rates.BRL)
require exchange
info "rate: 1 USD = $exchange BRL"

$query "select round((($usd)*$exchange)::numeric, 2)"
