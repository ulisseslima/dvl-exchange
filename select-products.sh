#!/bin/bash -e
# @installable
# products search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

and="1=1"
brand="2=2"
order_by='total_amount desc'

start="(now()::date - interval '1 month')"
end="now()"

today="now()::date"
kotoshi=$(now.sh -y)

while test $# -gt 0
do
    case "$1" in
    --where|-w)
        shift
        and="$1"
    ;;
    --brand|-b)
        shift
        # eg for many brands: TICKER_A|TICKER_B...
        brand="brand ~* '$1'"
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
    -*)
        echo "bad option '$1'"
    ;;
    esac
    shift
done

interval="$start and $end"

$query "select
  product.id,
  product.name,
  product.brand,
  round((1 * sum(op.price)::numeric / sum(op.amount)::numeric), 2) as avg_unit_price,
  sum(op.price) as total_spent,
  sum(op.amount) as total_amount
from product_ops op
join products product on product.id=op.product_id
join stores store on store.id=op.store_id
where op.created between $interval
and $and
and $brand
group by product.id
order by
  $order_by
" --full

info "total spending of products between $($query "select $start") and $($query "select $end")"
$query "select
  round(sum(op.price), 2) as total
from product_ops op
where op.created between $interval
and $and
and $brand
"
