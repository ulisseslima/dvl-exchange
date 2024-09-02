#!/bin/bash -e
# @installable
# snapshot from today's tickers
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)
source $MYDIR/db.sh

query=$MYDIR/psql.sh

start=$($query "select date_trunc('day',created)::date from dividends where currency = 'BRL' order by created desc limit 1")
# cei apparently requires a very specific end date limit:
limit=$(dop "(now() - interval '2 days')::date")

end=$(dop "('$start'::date + interval '30 days')::date")
if [[ $(dop "'$end' > now()") == t ]]; then
  end="$limit"
fi

while test $# -gt 0
do
  case "$1" in
    --start)
      shift
      start="${1}"
    ;;
    --end)
      shift
      end="$1"
    ;;
    -*)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac

  shift
done

info "updating with CEI ... date range: $start to $end"
# 'ultimas' is easier to use but very limited. no timestamps and only last week range
#response=$($MYDIR/api-cei.sh GET "extrato/v1/movimentacao/ultimas")
#response=$($MYDIR/api-cei.sh GET "extrato-movimentacao/v1.1/movimentacao/1" "dataInicio=2022-05-31&dataFim=2022-06-30")
#response=$($MYDIR/api-cei.sh GET "extrato-movimentacao/v1.2/movimentacao/1" "dataInicio=$start&dataFim=$end")
response=$($MYDIR/api-cei.sh GET "extrato-movimentacao/v2/movimentacao" "dataInicio=$start&dataFim=$end")
echo "$response"

if [[ -z "$response" ]]; then
    err "no response from CEI, check token"
    exit 1
fi

if [[ "$response" == not-authorized ]]; then
    err "logged out. you need to update key info in $LOCAL_ENV - https://www.investidor.b3.com.br/"

    # prompt_conf CEI_KEY_GUID "CEI cache-guid"
    prompt_conf CEI_KEY_BEARER "CEI Auth Bearer"

    exit 7
fi

node $MYDIR/process-sync-cei.js "$response"
debug "node: $?/$!"

info "done"
# echo "$response" | jq

# TODO sync br-indexes from last inserted date to now
