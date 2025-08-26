#!/bin/bash -e
# @installable
# snapshot from todays' stock prices ↑
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

psql=$MYDIR/psql.sh

plot="'plot:minper'"
show='--full'
filter="(now()::date - interval '1 month')"
fname=year
cols="(select id from assets where ticker_id=ticker.id) ass,
  ticker.name,
  max(snap.price)||' ('||
    (round(((max(snap.price)-(select price(ticker.id)))*100/(select price(ticker.id))),2))
    ||'%)' as \"max (%)\",
  round(avg(snap.price),2) as avg,
  (round(((round(avg(snap.price),2)-(select price(ticker.id)))*100/(select price(ticker.id))),2)) as avgper,
  min(snap.price) as min,
  (round(((min(snap.price)-(select price(ticker.id)))*100/(select price(ticker.id))),2)) as minper,
  (select
    (case
      when (select price(ticker.id)) < avg(snap.price) then '↓ '
      when (select price(ticker.id)) > avg(snap.price) then '^ '
      else ''
    end) 
    || price(ticker.id) ||
    (case
      when (select price(ticker.id)) <= min(snap.price) then ' !!!'
      when (select price(ticker.id)) = avg(snap.price) then ' -'
      when (select price(ticker.id)) >= max(snap.price) then ' X'
      else ''
    end)) now,
  last_buy(ticker.id) as last_buy,
  avg_buy(ticker.id) as avg_buy,
  max(snap.currency) currency
"

while test $# -gt 0
do
  case "$1" in
    --today|-t)
      filter='now()::date'
      fname=today
    ;;
    --week|-w)
      filter="(now()::date - interval '1 week')"
      fname=week
    ;;
    --month|-m)
      filter="(now()::date - interval '1 month')"
      fname=month
    ;;
    --year|-y)
      filter="(now()::date - interval '1 year')"
      fname=year
    ;;
    --custom)
      shift
      filter="$1"
      fname="$filter"
    ;;
    --csv)
      show='--csv'
    ;;
    --currency|-c)
      shift
      conditions="$conditions and snap.currency = '${1^^}'"
    ;;
    --short)
      cols="(select id from assets where ticker_id=ticker.id) ass,
        ticker.name,
        (round(((min(snap.price)-(select price(ticker.id)))*100/(select price(ticker.id))),2)) as minper,
        (select
          (case
            when (select price(ticker.id)) < avg(snap.price) then '↓ '
            when (select price(ticker.id)) > avg(snap.price) then '^ '
            else ''
          end) 
          || price(ticker.id) ||
          (case
            when (select price(ticker.id)) <= min(snap.price) then ' !!!'
            when (select price(ticker.id)) = avg(snap.price) then ' -'
            when (select price(ticker.id)) >= max(snap.price) then ' X'
            else ''
          end)) now,
        last_buy(ticker.id) as last_buy,
        avg_buy(ticker.id) as avg_buy,
        max(snap.currency) currency
      "
    ;;
    *)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac
  shift
done

info "$fname's snapshot, ordered by cheapest price now (compared to $(dop "${filter}::date")):"

query="select
  ${cols},
  ${plot}
from snapshots snap
join tickers ticker on ticker.id=snap.ticker_id
join snapshots latest on latest.id=snap.id
left join snapshots latest_x on latest_x.id=snap.id and latest_x.id>latest.id
where snap.created > $filter
and latest_x is null
$conditions
group by ticker.id
order by 
  currency,
  (select price(ticker.id)-(min(snap.price)))
"

$psql "$($MYDIR/plotter.sh "$query")" $show
