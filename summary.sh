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

psql=$MYDIR/psql.sh

simulation=false
today="now()::date"
fname=month
interval="($today - interval '1 month') and $today"

while test $# -gt 0
do
  case "$1" in
      --today)
        interval="$today and ($today + interval '1 day')"
        fname=today
      ;;
      --week)
        interval="($today - interval '1 week') and $today"
        fname=week
      ;;
      --month)
        interval="($today - interval '1 month') and $today"
        fname=month
      ;;
      --year)
        if [[ -n "$2" && "$2" != "-"* ]]; then
          shift
          y=$1
          interval="'$y-01-01' and ('$y-01-01'::timestamp + interval '1 year')"
        else
          interval="($today - interval '1 year')"
        fi
        fname=year
      ;;
      --custom)
        shift
        interval="$1"
        fname="$interval"
      ;;
      --simulation|--sim)
        simulation=true
      ;;
      -*)
        echo "$(sh_name $ME) - bad option '$1'"
        exit 1
      ;;
  esac
  shift
done

# info "$fname's snapshot, ordered by cheapest average price:"
# $psql "select
#   asset.id||'/'||ticker.id asset_ticker,
#   ticker.name,
#   asset.amount,
#   asset.cost,
#   asset.value ||' ('||
#     (round(((asset.value-asset.cost)*100/asset.cost), 2))
#     ||'%)' as \"curr_val (%)\",
#   (asset.amount*max(snap.price)) ||' ('||
#     (round((((asset.amount*max(snap.price))-asset.cost)*100/asset.cost), 2))
#     ||'%)' as \"max_val (%)\",
#   (round((asset.amount*avg(snap.price)), 2)) ||' ('||
#     (round((((round((asset.amount*avg(snap.price)), 2))-asset.cost)*100/asset.cost), 2))
#     ||'%)' as \"avg_val (%)\",
#   (asset.amount*min(snap.price)) ||' ('||
#     (round((((asset.amount*min(snap.price))-asset.cost)*100/asset.cost), 2))
#     ||'%)' as \"min_val (%)\",
#   max(snap.currency) currency
# from assets asset
# join tickers ticker on ticker.id=asset.ticker_id
# join snapshots snap on snap.ticker_id=ticker.id
# where snap.created between $interval
# and asset.amount > 0
# group by ticker.id, asset.id
# order by
#   max(snap.currency),
#   avg(snap.price)
# " --full

exchange=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .rates.BRL)
# \"$\"

WITH_AGGREGATED_INFO="with
prices as (
  select 
    price(asset.ticker_id) price, 
    ticker_id 
  from assets asset
),
groups as (
select
  ticker.id,
  ticker.name,
  sum(op.amount) amount,
  round(sum(op.price), 2) as cost, 
  round(max(p.price)*sum(op.amount), 2) as value,
  op.currency as currency
from assets asset
join tickers ticker on ticker.id=asset.ticker_id
join prices p on p.ticker_id=asset.ticker_id
join asset_ops op on op.asset_id=asset.id
where simulation is $simulation
group by 
  ticker.id,
  op.currency
)"

info "total investment cost/value:"
$psql "$WITH_AGGREGATED_INFO
select 
  currency,
  sum(cost) as cost,
  sum(value) as value
from groups g
group by g.currency
" --full

info -n "aggregate diff/% increase:"
$psql "$WITH_AGGREGATED_INFO
select 
  currency as \"$\",
  round(sum(value)-sum(cost), 2) as diff, 
  round(((sum(value)-sum(cost))*100/sum(value)), 2) as \"%\"
from groups g
group by currency
" --full

info -n "equity total:"
total=$($psql "$WITH_AGGREGATED_INFO
  select round(
    sum(
      case 
        when currency = 'USD' then value*$exchange
        else value
      end
    ), 2) as total
  from groups g
")
echo $total

info -n "grand total (equity+fixed income):"
query="select 'cost' as type, sum(amount) 
  from fixed_income
  union
  select 'dividends' as type, sum(total) 
  from earnings
  where source = 'fixed-income'
"

agg=$($psql "$query")
cost=$(echo "$agg" | head -1 | cut -d'|' -f2)
divs=$(echo "$agg" | tail -1 | cut -d'|' -f2)
echo "$(op.sh "${total}+(${cost}+${divs})")"
