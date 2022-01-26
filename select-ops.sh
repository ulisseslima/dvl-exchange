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

info "ops since '$($query "select $filter")'"
$query "select
  max(asset.id)||'/'||ticker.id \"ass/tick\",
  ticker.name,
  round((1 * op.price::numeric / op.amount::numeric), 2) as unit,
  op.*,
  (case when op.currency = 'USD' then (price*coalesce(op.rate, $rate))::text else '-' end) BRL
from asset_ops op
join assets asset on asset.id=op.asset_id
join tickers ticker on ticker.id=asset.ticker_id
where op.created > $filter
and $and
and $ticker
group by op.id, ticker.id
order by
  $order_by
" --full
