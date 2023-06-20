#!/bin/bash -e
# @installable
# get exchange rate for two currencies
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
fi

echo "$response"
