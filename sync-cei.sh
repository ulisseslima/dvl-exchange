#!/bin/bash -e
# @installable
# snapshot from todays' tickers
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

info "updating with CEI ..."
response=$($MYDIR/api-cei.sh GET "extrato/v1/movimentacao/ultimas")
echo "$response"

if [[ -z "$response" ]]; then
    err "no response from CEI, check token"
    exit 1
fi

if [[ "$response" == *"Authorization Required"* ]]; then
    err "logged out. you need to update key info in $LOCAL_ENV - https://www.investidor.b3.com.br/"
    exit 7
fi

node $MYDIR/process-sync-cei.js "$response"
debug "node: $?/$!"

info "done"
echo "$response" | jq
