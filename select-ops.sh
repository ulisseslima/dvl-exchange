#!/bin/bash -e
# @installable
# ops search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

psql=$MYDIR/psql.sh

and="1=1"
ticker="2=2"
grouping="op.id, ticker.id"
order_by='max(op.created)'

start="(now()::date - interval '1 month')"
end="CURRENT_TIMESTAMP"

today="now()::date"
this_month=$(now.sh -m)
kotoshi=$(now.sh -y)
simulation=false

while test $# -gt 0
do
    case "$1" in
    --ticker|-t)
        shift
        # eg for many tickers: TICKER_A|TICKER_B...
        ticker="ticker.name ~* '$1'"
    ;;
    --where|-w)
        shift
        and="$1"
    ;;
    --today)
        start="$today"
        end="($today + interval '1 day')"
    ;;
    --week|-w)
        start="($today - interval '1 week')"
        end="$today"
    ;;
    --month|-m)
        if [[ -n "$2" && "$2" != "-"* ]]; then
            shift
            m=$1
            
            this_month_int=$(op.sh "${this_month}::int")
            month_int=$(op.sh "${m}::int")
            [[ $this_month_int -ge $month_int ]] && year=$kotoshi || year=$(($kotoshi-1))

            start="'$year-$m-01'"
            end="('$year-$m-01'::timestamp + interval '1 month')"
        else
            start="($today - interval '1 month')"
            end="$today"
        fi
    ;;
    --year|-y)
        if [[ -n "$2" && "$2" != "-"* ]]; then
            shift
            y=$1
            start="'$y-01-01'"
            end="('$y-01-01'::timestamp + interval '1 year')"
        else
            start="($today - interval '1 year')"
            end="$today"
        fi
    ;;
    --until|-u)
        shift
        cut=$1
        start="'1900-01-01'"
        end="'$1'"
    ;;
    --all|-a)
        start="'1900-01-01'"
        end="now()"
    ;;
    --order-by|-o)
        shift
        order_by="$1"
    ;;
    --simulation|--sim)
        simulation=true
    ;;
    --currency|-c)
        shift
        and="$and and op.currency='${1^^}'"
    ;;
    --kind|-k)
        shift
        and="$and and ticker.kind='${1^^}'"
    ;;
    --buys)
        and="$and and op.kind='BUY'"
    ;;
    --sells)
        and="$and and op.kind='SELL'"
    ;;
    --group-by|-g)
        shift
        grouping="$1"
    ;;
    -*)
        echo "$(sh_name $ME) - bad option '$1'"
        exit 1
    ;;
    esac
    shift
done

interval="$start and $end"

rate=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .rates.BRL)
require rate

info "ops between $($psql "select $start") and $($psql "select $end")"
query="select
  max(asset.id)||'/'||ticker.id \"ass/tick\",
  ticker.name,
  round((1 * op.price::numeric / op.amount::numeric), 2) as unit,
  op.id,op.kind,op.amount,op.price,op.currency,op.created,op.rate,
  (case when op.currency = 'USD' then round((price*coalesce(op.rate, $rate)),2)::text else '-' end) BRL
from asset_ops op
join assets asset on asset.id=op.asset_id
join tickers ticker on ticker.id=asset.ticker_id
where op.created between $interval
and $and
and simulation is $simulation
and $ticker
group by $grouping
order by
  $order_by
"

$psql "$query" --full
debug "$query"

info "aggregated sum [same value, different currencies]:"
query="select
  round(sum(
    (case when op.currency = 'USD' then
      (price*rate)
      else
      price
    end)
  ), 2) BRL,
  round(sum(
    (case when op.currency = 'BRL' then
      (price/$rate)
      else
      price
    end)
  ), 2) USD
from asset_ops op
join assets asset on asset.id=op.asset_id
join tickers ticker on ticker.id=asset.ticker_id
where op.created between $interval
and simulation is $simulation
and $and
and $ticker
"

$psql "$query" --full
debug "$query"
