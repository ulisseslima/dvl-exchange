#!/bin/bash -e
# @installable
# dividends search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

start="(now()::date - interval '1 month')"
end="now()"

and="1=1"
ticker="2=2"
order_by='max(op.created)'

today="now()::date"
kotoshi=$(now.sh -y)

while test $# -gt 0
do
    case "$1" in
    --where)
        shift
        and="$1"
    ;;
    --ticker|-t)
        shift
        ticker="ticker.name ilike '$1%'"
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
            start="'$kotoshi-$m-01'"
            end="('$kotoshi-$m-01'::timestamp + interval '1 month')"
        else
            start="($today - interval '1 month')"
            end="$today"
        fi
    ;;
    --year|-y)
        if [[ "$2" != "-"* ]]; then
            shift
            y=$1
            start="'$y-01-01'"
            end="('$y-01-01'::timestamp + interval '1 year')"
        else
            start="($today - interval '1 year')"
            end="$today"
        fi
    ;;
    --until)
        shift
        cut=$1
        interval="'1900-01-01' and '$1'"
    ;;
    --all|-a)
        interval="'1900-01-01' and now()"
    ;;
    --order-by|-o)
        shift
        order_by="$1"
    ;;
    -*)
        echo "bad option '$1'"
    ;;
    esac
    shift
done

interval="$start and $end"

rate=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .response.rates.BRL)
require rate
info "today's rate: $rate"

info "dividends between $($query "select $start") and $($query "select $end")"
$query "select
  op.ticker_id,
  ticker.name,
  op.*,
  (case when op.currency = 'USD' then round((total*$rate), 2)::text else total::text end) BRL
from dividends op
join tickers ticker on ticker.id=op.ticker_id
where op.created between $interval
and $and
and $ticker
group by op.id, ticker.id
order by
  $order_by
" --full

info "sum (BRL):"
$query "select round(sum(
  (case when op.currency = 'USD' then 
    (total*$rate) else 
    total 
  end)
), 2)
from dividends op
join tickers ticker on ticker.id=op.ticker_id
where op.created between $interval
and $and
and $ticker
"
