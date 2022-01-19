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

store_name="${1^^}";      require store_name
product_name="${2^^}";    require product_name
product_brand="${3^^}";   require product_brand
price="$4";               require -n price
amount="$5";              [[ -z "$amount" ]] && amount=1
created="$6";             [[ -z "$created" ]] && created=$(now.sh -d)
currency="${7^^}";        [[ -z "$currency" ]] && currency=$DEFAULT_CURRENCY

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

