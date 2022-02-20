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

filter="(now()::date - interval '1 month')"
and="1=1"
ticker="2=2"
order_by='max(op.created) desc'

while test $# -gt 0
do
    case "$1" in
    --where|-w)
        shift
        and="$1"
    ;;
    --ticker|-t)
        shift
        ticker="ticker.name ilike '$1%'"
    ;;
    --filter|-f)
        shift
        case "$1" in
            today)
                filter='now()::date'
            ;;
            week)
                filter="(now()::date - interval '1 week')"
            ;;
            month)
                filter="(now()::date - interval '1 month')"
            ;;
            year)
                filter="(now()::date - interval '1 year')"
            ;;
            none)
                filter="'2000-01-01'"
            ;;
        esac
    ;;
    --all|-a)
        filter="'2000-01-01'"
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

rate=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .response.rates.BRL)
require rate
info "today's rate: $rate"

info "dividends since '$($query "select $filter")'"
$query "select
  op.ticker_id,
  ticker.name,
  op.*,
  (case when op.currency = 'USD' then round((total*$rate), 2)::text else total::text end) BRL
from dividends op
join tickers ticker on ticker.id=op.ticker_id
where op.created > $filter
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
where op.created > $filter
and $and
and $ticker
"
