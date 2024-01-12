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

summary=false
simulation=false
interval="'1900-01-01' and now()"
ticker=""
show='--full'
order="max(op.currency),
  diff desc,
  n desc
"

today="now()::date"
while test $# -gt 0
do
  case "$1" in
    --all|-a)
      interval="'1900-01-01' and now()"
    ;;
    --today|-n)
      interval="$today and ($today + interval '1 day')"
    ;;
    --week|-w)
      interval="($today - interval '1 week') and $today"
    ;;
    --month|-m)
      interval="($today - interval '1 month') and $today"
    ;;
    --year|-y)
      if [[ -n "$2" && "$2" != "-"* ]]; then
        shift
        y=$1
        interval="'$y-01-01' and ('$y-01-01'::timestamp + interval '1 year')"
      else
        interval="($today - interval '1 year') and $today"
      fi
    ;;
    --until|-u)
      shift
      cut=$1
      interval="'1900-01-01' and '$1'"
    ;;
    --custom|-c)
      shift
      interval="$1"
    ;;
    --ticker|-t)
      shift
      ticker="and ticker.name ilike '${1,,}%'"
    ;;
    --short|-s)
      show=""
    ;;
    --simulation|--sim)
      simulation=true
    ;;
    --summary|--sum)
      summary=true
    ;;
    --select)
      shift
      cols="$cols ,$1"
    ;;
    --order-by-val)
      order="max(op.currency),
      curr_val desc,
      n desc"
    ;;
    -*)
      echo "$(sh_name $ME) - bad option '$1'"
    ;;
  esac
  shift
done

info "$interval's position, ordered by: $(echo $order):"
if [[ -n "$ticker" ]]; then
  info "$ticker"
fi

$query "select
  max(asset.id)||'/'||ticker.id asstck,
  ticker.name ticker,
  round(sum(op.amount), 2) as n,
  sum(op.price) as cost,
  max(op.currency) as \"$\",
  round(sum(op.price*op.rate), 2) as BRL,
  round(price(ticker.id)*sum(op.amount), 2) as curr_val,
  percentage_diff(price(ticker.id)*sum(op.amount), sum(op.price)) as diff
  $cols
from asset_ops op
join assets asset on asset.id=op.asset_id
join tickers ticker on ticker.id=asset.ticker_id
where op.created between $interval
and simulation is $simulation
$ticker
group by op.asset_id, ticker.id
order by
  $order
" $show
