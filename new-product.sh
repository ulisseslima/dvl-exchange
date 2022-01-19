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

if [[ $# -lt 1 ]]; then
  info "e.g.: $0 WALMART BREAD 1.85 2 '2020-12-02' USD"
  exit 0
fi

store_name="${1^^}";      require --nan store_name; shift
product_name="${1^^}";    require --nan product_name; shift
product_brand="${1^^}";   require --nan product_brand; shift
price="$1";               require -nx price; shift
amount="$1";              require -nx amount; shift

while test $# -gt 0
do
    case "$1" in
    --date|-d)
      shift 
      created="$1"
    ;;
    --currency|-c)
      shift
      currency="$1"
    ;;
    --expression|-x)
      shift
      expression="$1"
    ;;
    -*) 
      echo "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

[[ -z "$created" ]] && created="$(now.sh -d)"
[[ -z "$currency" ]] && currency=$DEFAULT_CURRENCY

if [[ -n "$expression" ]]; then
  price="${price} ${expression}"
  amount="${amount} ${expression}"

  echo "price: $price, amount: $amount"
fi

store_id=$($query "select id from stores where name = '${store_name}' or name iLIKE '%${store_name}%' limit 1")
if [[ -z "$store_id" ]]; then
  info "creating new store: $store_name"
  store_id=$($query "insert into stores (name) values ('$store_name') returning id")
  echo "#$store_id"
fi

product_id=$($query "select id from products where (name = '${product_name}' or name iLIKE '%${product_name}%') and brand iLIKE '%${product_brand}%' limit 1")
if [[ -z "$product_id" ]]; then
  info "creating new product: $product_name ($product_brand)"
  product_id=$($query "insert into products (name, brand) values ('$product_name', '$product_brand') returning id")
  echo "#$product_id"
fi

id=$($query "insert into product_ops (store_id, product_id, amount, price, currency, created)
  select $store_id, $product_id, $amount, $price, '$currency', '$created'
  returning id
")

if [[ -n "$id" ]]; then
  info "success: $id"

  info "total cost:"
  $query "select sum(price) from product_ops where product_id = $product_id"

  $MYDIR/product-summary.sh "$product_name"
fi

