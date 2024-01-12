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
#order_by='total_amount desc'
order_by='total_spent desc'

start="(now()::date - interval '1 month')"
end="CURRENT_TIMESTAMP"

today="now()::date"
this_month=$(now.sh -m)
kotoshi=$(now.sh -y)
simulation=false

# TODO special characters in pdf.sh (just use csv?)
# store: 14
# product: 22
# brand: 13
max_width=100

while test $# -gt 0
do
    case "$1" in
    --where|-w)
        shift
        and="$1"
    ;;
    --name|-p)
        shift
        name="${1^^}"
        and="$and and product.name like '%${name}%'"
    ;;
    --store|-s|--from)
        shift
        name="${1^^}"
        and="$and and upper(store.name) like '%${name}%'"
    ;;
    --category|--cat|-c)
        shift
        name="${1^^}"
        category_filter=true
        and="$and and store.category like '%${name}%'"
    ;;
    --brand|-b)
        shift
        # eg for many brands: BRAND_A|BRAND_B...
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
    --width)
        shift
        max_width=$1
    ;;
    --month|-m)
        if [[ -n "$2" && "$2" != "-"* ]]; then
            shift
            m=$1
            
            [[ $this_month -ge $m ]] && year=$kotoshi || year=$(($kotoshi-1))

            start="'$year-$m-01'"
            end="('$year-$m-01'::timestamp + interval '1 month')"
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
        end="CURRENT_TIMESTAMP"
    ;;
    --order-by|-o)
        shift
        order_by="$1"
    ;;
    --simulation|--sim)
      simulation=true
    ;;
    -*)
        echo "$(sh_name $ME) - bad option '$1'"
    ;;
    esac
    shift
done

interval="$start and $end"

$query "select
  substring(max(store.name), 0, $max_width) store,
  product.id,
  substring(product.name, 0, $max_width) product,
  substring(product.brand, 0, $max_width) brand,
  round((1 * sum(op.price)::numeric / sum(op.amount)::numeric), 2) as avg_unit_price,
  sum(op.price) as total_spent,
  sum(op.amount) as total_amount
from product_ops op
join products product on product.id=op.product_id
join stores store on store.id=op.store_id
where op.created between $interval
and simulation is $simulation
and $and
and $brand
group by product.id
order by
  $order_by
" --full

if [[ -z "$category_filter" ]]; then
    info -n "total spending of products between $($query "select $start") and $($query "select $end") by category"
    $query "select 
      store.category,
      round(sum(op.price), 2) as total_spent,
      round(sum(op.amount), 2) as total_amount
    from product_ops op
    join products product on product.id=op.product_id
    join stores store on store.id=op.store_id
    where op.created between $interval
    and simulation is $simulation
    and $and
    and $brand
    group by store.category
    order by $order_by
    " --full
fi

info -n "total spending of products between $($query "select $start") and $($query "select $end")"
$query "select
  round(sum(op.price), 2) as total_spent,
  round(sum(op.amount), 2) as total_amount
from product_ops op
join products product on product.id=op.product_id
join stores store on store.id=op.store_id
where op.created between $interval
and simulation is $simulation
and $and
and $brand
" --full
