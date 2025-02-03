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
    --where)
        shift
        and="$1"
    ;;
    --like)
        shift
        name="${1^^}"
        and="$and and similarity(store.name||' '||product.name||' '||brand, '${name}') > 0.15"
    ;;
    --tags|-t)
      shift
      and="$and and op.tags like '%${1^^}%'"
    ;;
    --product-tags)
      shift
      and="$and and product.tags like '%${1^^}%'"
    ;;
    --untagged)
      and="$and and op.tags is null"
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
        end="($today + interval '1 day')"
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
            end="($today + interval '1 day')"
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
            end="($today + interval '1 day')"
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
        exit 1
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
    extra_cols="op.id as op,"
    main_ordering="op.created,${ordering}"
else
    main_ordering="$ordering"
fi

$query "select ${extra_cols}
  max(op.created) as last,
  max(store.category) as category,
  substring(max(store.name), 0, $max_width) as store,
  product.id,
  substring(product.name, 0, $max_width) as product,
  substring(product.brand, 0, $max_width) as brand,
  round((1 * sum(op.price)::numeric / sum(op.amount)::numeric), 2) as avg_unit_price,
  sum(op.price) as total_spent,
  sum(op.amount) as total_amount,
  count(op.id) as buys,
  array_agg(distinct op.tags) as tags
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
      max(op.created) as last,
      store.category,
      round(sum(op.price), 2) as total_spent,
      round(sum(op.amount), 2) as total_amount,
      (array_agg(distinct product.name))[1:2] as examples
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
