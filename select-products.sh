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
grouping=product.id
#ordering='total_amount desc'
ordering='total_spent desc'

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
        brand="brand ~* '${1^^}'"
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
        end="'2900-01-01'"
    ;;
    --order-by|-o)
        shift
        ordering="$1"
    ;;
    --simulation|--sim)
      simulation=true
    ;;
    --group*|-g)
      shift
      grouping="$1"
      if [[ "$grouping" == ops ]]; then
        grouping="product.id,op.id"
      fi
    ;;
    -*)
        echo "$(sh_name $ME) - bad option '$1'"
    ;;
    esac
    shift
done

interval="$start and $end"
interval_clause="op.created between $interval"
if [[ $start == 1900* && $end == *2900 ]]; then
    interval_clause="1=1"
fi

if [[ "$grouping" == *'op.id'* ]]; then
    extra_cols="op.id,op.created,"
    main_ordering="op.created,${ordering}"
else
    main_ordering="$ordering"
fi

$query "select ${extra_cols}
  max(op.created) last,
  max(store.category) category,
  substring(max(store.name), 0, $max_width) store,
  product.id,
  substring(product.name, 0, $max_width) product,
  substring(product.brand, 0, $max_width) brand,
  round((1 * sum(op.price)::numeric / sum(op.amount)::numeric), 2) as avg_unit_price,
  sum(op.price) as total_spent,
  sum(op.amount) as total_amount,
  count(op.id) as buys
from product_ops op
join products product on product.id=op.product_id
join stores store on store.id=op.store_id
where $interval_clause
and simulation is $simulation
and $and
and $brand
group by $grouping
order by $main_ordering
" --full

if [[ -z "$category_filter" ]]; then
    info -n "total spending of products between $($query "select $start") and $($query "select $end") by category"
    $query "select 
      max(op.created) last,
      store.category,
      round(sum(op.price), 2) as total_spent,
      round(sum(op.amount), 2) as total_amount,
      (array_agg(product.name))[1:2] examples
    from product_ops op
    join products product on product.id=op.product_id
    join stores store on store.id=op.store_id
    where $interval_clause
    and simulation is $simulation
    and $and
    and $brand
    group by store.category
    order by $ordering
    " --full
fi

info -n "total spending of products between $($query "select $start") and $($query "select $end")"
$query "select
  round(sum(op.price), 2) as total_spent,
  round(sum(op.amount), 2) as total_amount
from product_ops op
join products product on product.id=op.product_id
join stores store on store.id=op.store_id
where $interval_clause
and simulation is $simulation
and $and
and $brand
" --full
