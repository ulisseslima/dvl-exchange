#!/bin/bash -e
# @installable
# your assets position on a date range
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

interval="'1900-01-01' and now()"
ticker=""
show='--full'

today="now()::date"
while test $# -gt 0
do
  case "$1" in
    --all)
      interval="'1900-01-01' and now()"
    ;;
    --today)
      interval="$today and ($today + interval '1 day')"
    ;;
    --week)
      interval="($today - interval '1 week') and $today"
    ;;
    --month)
      interval="($today - interval '1 month') and $today"
    ;;
    --year)
      if [[ -n "$2" && "$2" != "-"* ]]; then
        shift
        y=$1
        interval="'$y-01-01' and ('$y-01-01'::timestamp + interval '1 year')"
      else
        interval="($today - interval '1 year') and $today"
      fi
    ;;
    --until)
      shift
      cut=$1
      interval="'1900-01-01' and '$1'"
    ;;
    --custom)
      shift
      interval="$1"
    ;;
    --ticker|-t)
      shift
      ticker="and ticker.name ilike '${1,,}%'"
    ;;
    --short)
      show=""
    ;;
    -*)
      echo "bad option '$1'"
    ;;
  esac
  shift
done

info "$interval's position, ordered by currency, amount and name:"
if [[ -n "$ticker" ]]; then
  info "$ticker"
fi

$query "select
  max(asset.id)||'/'||ticker.id asset_ticker,
  ticker.name,
  sum(op.amount) as n,
  sum(op.price) as cost,
  max(op.currency) currency
from asset_ops op
join assets asset on asset.id=op.asset_id
join tickers ticker on ticker.id=asset.ticker_id
where op.created between $interval 
$ticker
group by op.asset_id, ticker.id
order by
  max(op.currency),
  n desc,
  ticker.name
" $show
