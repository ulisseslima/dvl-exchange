#!/bin/bash -e
# @installable
# snapshot from todays' stock prices
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

fname=${1:---month}
case "$fname" in
    --today)
        filter='now()::date'
    ;;
    --week)
        filter="(now()::date - interval '1 week')"
    ;;
    --month)
        filter="(now()::date - interval '1 month')"
    ;;
    --year)
        filter="(now()::date - interval '1 year')"
    ;;
    --custom)
        shift
        filter="$1"
    ;;
    -*)
        echo "bad option '$1'"
    ;;
esac

info "$fname's snapshot, ordered by cheapest average price:"

$query "select
  (select id from assets where ticker_id=ticker.id) asset_id,
  ticker.name,
  max(snap.price)||' ('||
    (round(((max(snap.price)-(select price(ticker.id)))*100/(select price(ticker.id))), 2))
    ||'%)' as \"max (%)\",
  round(avg(snap.price), 2)||' ('||
    (round(((round(avg(snap.price), 2)-(select price(ticker.id)))*100/(select price(ticker.id))), 2))
    ||'%)' as \"avg (%)\",
  min(snap.price)||' ('||
    (round(((min(snap.price)-(select price(ticker.id)))*100/(select price(ticker.id))), 2))
    ||'%)' as \"min (%)\",
  (select price(ticker.id) || 
    (case 
      when (select price(ticker.id)) <= min(snap.price) then ' !!!' 
      when (select price(ticker.id)) >= max(snap.price) then ' X' 
      else '' 
    end)) now,
  max(snap.currency) currency
from snapshots snap
join tickers ticker on ticker.id=snap.ticker_id
where snap.created > $filter
group by ticker.id
order by 
  max(snap.currency),
  avg(snap.price)
" --full