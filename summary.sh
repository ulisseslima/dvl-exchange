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
today="now()::date"
case "$fname" in
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
    --custom)
        shift
        interval="$1"
    ;;
    -*)
        echo "bad option '$1'"
    ;;
esac

info "$interval's snapshot, ordered by cheapest average price:"
$query "select
  asset.id||'/'||ticker.id asset_ticker,
  ticker.name,
  asset.amount,
  asset.cost,
  asset.value ||' ('||
    (round(((asset.value-asset.cost)*100/asset.cost), 2))
    ||'%)' as \"curr_val (%)\",
  (asset.amount*max(snap.price)) ||' ('||
    (round((((asset.amount*max(snap.price))-asset.cost)*100/asset.cost), 2))
    ||'%)' as \"max_val (%)\",
  (round((asset.amount*avg(snap.price)), 2)) ||' ('||
    (round((((round((asset.amount*avg(snap.price)), 2))-asset.cost)*100/asset.cost), 2))
    ||'%)' as \"avg_val (%)\",
  (asset.amount*min(snap.price)) ||' ('||
    (round((((asset.amount*min(snap.price))-asset.cost)*100/asset.cost), 2))
    ||'%)' as \"min_val (%)\",
  max(snap.currency) currency
from assets asset
join tickers ticker on ticker.id=asset.ticker_id
join snapshots snap on snap.ticker_id=ticker.id
where snap.created between $interval
and asset.amount > 0
group by ticker.id, asset.id
order by
  max(snap.currency),
  avg(snap.price)
" --full

exchange=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .response.rates.BRL)

info "total investment cost/value:"

total_brl=$($query "select sum(value) from assets asset where currency = 'BRL'")
total_usd_to_brl=$($query "select round(sum(value*$exchange), 2) from assets asset where currency = 'USD'")

$query "select 
  'BRL' as \"$\", 
  sum(cost) as cost, 
  $total_brl as value, 
  '-' as \"BRL\"
from assets asset
where currency = 'BRL'
union
select 
  'USD' as \"$\", 
  round(sum(cost), 2) as cost, 
  round(sum(value), 2) as value, 
  '$total_usd_to_brl' as \"BRL\"
from assets asset
where currency = 'USD'
" --full
echo "=$($query "select $total_brl+$total_usd_to_brl") BRL"

info "aggregate diff/% increase:"
$query "select 
  currency as \"$\",
  round(sum(value)-sum(cost), 2) as diff, 
  round(((sum(value)-sum(cost))*100/sum(value)), 2) as \"%\"
from assets asset
group by currency
" --full
