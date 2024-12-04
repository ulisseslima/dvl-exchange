#!/bin/bash -e
# @installable
# adds a new product buy to keep track of inflation and control expenses
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

product_name="${1^^}"
require product_name
shift

if [[ "$product_name" == '*' || "$product_name" == 'ANY' ]]; then
  product_name='%'
fi

brand="product.brand=product.brand"
store="store.id=store.id"
limit=5
latest=$limit

period="$(interval - '1 year')"
interval="('$period'::date+interval '1 year')"

while test $# -gt 0
do
    case "$1" in
    --simulation|--sim)
      shift
      simulation="and simulation is $1"
    ;;
    --brand|-b)
      shift
      brand="product.brand ilike '%$1%'"
    ;;
    --from|--store|-s)
      shift
      store="store.name ilike '%$1%'"
    ;;
    --limit|-l)
      shift
      limit="$1"
    ;;
    --latest)
      shift
      latest=$1
    ;;
    --month|-m)
      shift
      month="$1"
      
      period="$(now.sh -y)-$month-01"
      interval="('$period'::date+interval '1 month')"
    ;;
    --period)
      shift
      period="$1"
      type="$(count-char.sh "$period" '-')"
      case "$type" in
        0)
          period="$period-$(now.sh -m)-01"
          interval="('$period'::date+interval '1 year')"
        ;;
        1)
          period="$period-01"
          interval="('$period'::date+interval '1 month')"
        ;;
        2)
          interval="('$period'::date+interval '1 month')"
        ;;
        *)
          echo "bad period '$period'"
        ;;
      esac
    ;;
    -*)
        echo "$(sh_name $ME) - bad option '$1'"
        exit 1
    ;;
    esac
    shift
done

#info "total bought:"
#$query "select sum(price) from product_ops where product_id = $product_id"

info "$store - $product_name [$brand] - latest buys:"
$query "select 
  op.id op, store.name store, 
  store.id||'#'||product.id sid_pid, 
  product.name product, product.brand, 
  amount, price, op.currency cur, 
  op.created,
  round((1 * price / amount), 2) as unit
  from product_ops op
  join products product on product.id=op.product_id
  join stores store on store.id=op.store_id  
  where (product.name = '${product_name}' or product.name iLIKE '%${product_name}%')
  and $brand
  and $store
  $simulation
order by op.created desc, op.id desc 
limit $limit" --full

# info "average price considering period between '$period' and '$interval':"
# $query "select
#     product.id,
#     product.name product,
#     product.brand,
#     round(avg(price), 2) as price,
#     max(op.currency) cur,
#     round((1 * sum(price) / sum(amount)), 2) as unit,
#     product.extra->'carbs' \"carbs%\"
#   from product_ops op
#   join products product on product.id=op.product_id
#   join stores store on store.id=op.store_id  
#   where (product.name = '${product_name}' or product.name iLIKE '%${product_name}%')
#   and $brand
#   and $store
#   $simulation
#   and op.created between '$period' and $interval
# group by product.id, product.brand
# order by max(op.created) desc 
# " --full

info "cheapest buys:"
$query "select 
  op.id op, store.name store, product.name product, product.brand,
  amount,
  price, op.currency cur,
  op.created,
  round((1 * price / amount), 2) as unit
  from product_ops op
  join products product on product.id=op.product_id
  join stores store on store.id=op.store_id  
  where (product.name = '${product_name}' or product.name iLIKE '%${product_name}%')
  and $brand
  and $store
  $simulation
order by 
  unit,
  op.created
limit $limit" --full