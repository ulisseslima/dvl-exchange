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
full='--full'
filter="(now()::date - interval '1 month')"
fname=month

while test $# -gt 0
do
  case "$1" in
    --today)
      filter='now()::date'
      fname=today
    ;;
    --week)
      filter="(now()::date - interval '1 week')"
      fname=week
    ;;
    --month)
      filter="(now()::date - interval '1 month')"
      fname=month
    ;;
    --year)
      filter="(now()::date - interval '1 year')"
      fname=year
    ;;
    --custom)
      shift
      filter="$1"
      fname="$filter"
    ;;
    --csv)
      full='--csv'
    ;;
    -*)
      echo "$0 - bad option '$1'"
    ;;
  esac
  shift
done

info "$fname's snapshot, ordered by cheapest price now:"

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
join snapshots latest on latest.id=snap.id
left join snapshots latest_x on latest_x.id=snap.id and latest_x.id>latest.id
where snap.created > $filter
and latest_x is null
group by ticker.id
order by 
  max(snap.currency),
  min(latest.price)
" $full