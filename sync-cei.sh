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

start=$($query "select date_trunc('day',created)::date from dividends where currency = 'BRL' order by created desc limit 1")
# cei apparently requires a very specific end date:
end=$(dop.sh "(now() - interval '3 days')::date")

info "updating with CEI ... date range: $start to $end"
# 'ultimas' is easier to use but very limited. no timestamps and only last week range
#response=$($MYDIR/api-cei.sh GET "extrato/v1/movimentacao/ultimas")
#response=$($MYDIR/api-cei.sh GET "extrato-movimentacao/v1.1/movimentacao/1" "dataInicio=2022-05-31&dataFim=2022-06-30")
response=$($MYDIR/api-cei.sh GET "extrato-movimentacao/v1.2/movimentacao/1" "dataInicio=$start&dataFim=$end")
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
