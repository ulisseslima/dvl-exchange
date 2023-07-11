#!/bin/bash -e
# @installable
# get exchange rate for two currencies
# e.g.: usd-rate-on.sh usd rate on a specific date:
# dvlx-scoop-rate USD -x BRL --date "$date" | jq -r .rates.BRL
# note: used to be | jq -r .response.rates.BRL
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh
api=$MYDIR/api-currency-scoop.sh

currency="$1"; shift
mode=latest

require currency

while test $# -gt 0
do
    case "$1" in
    -x)
      shift
      symbols="$1"
    ;;
    --date|--created|-d)
      shift
      date="$(echo $1 | cut -d' ' -f1)"
      mode=historical

      info "data from $date"
    ;;
    -*)
      echo "$0 - bad option '$1'"
    ;;
    esac
    shift
done

require symbols

response=$($api GET "v1/$mode?base=$currency&symbols=$symbols&date=$date")
if [[ -z "$response" ]]; then
  err "no response, returning last known snapshot..."
  response=$($query "select '{\"response\":{\"date\":\"'||s.created::date||'\",\"rates\":{\"BRL\":'||s.price||'}}}' from snapshots s join tickers t on t.id=s.ticker_id where t.name = 'USD-BRL' order by s.id desc limit 1")
else
  exchange=$(echo "$response" | jq -r .rates.BRL)
  if [[ -z "$date" ]]; then
    date=$(now.sh -dt)
  fi
  
  $query "insert into snapshots
  (ticker_id, price, currency, created)
  values 
  ((select id from tickers where name = 'USD-BRL' limit 1), $exchange, 'BRL', '$date')"
fi

echo "$response"
