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

fname=${1:---all}
today="now()::date"
case "$fname" in
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
      if [[ "$2" != "-"* ]]; then
        shift
        y=$1
        interval="'$y-01-01' and ('$y-01-01'::timestamp + interval '1 year')"
      else
        interval="($today - interval '1 year')"
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
    -*)
      echo "bad option '$1'"
    ;;
esac

info "$interval's position, ordered by currency, amount and name:"
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
group by op.asset_id, ticker.id
order by
  max(op.currency),
  n desc,
  ticker.name
" --full
