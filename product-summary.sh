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

#info "total bought:"
#$query "select sum(price) from product_ops where product_id = $product_id"

info "latest buys:"
$query "select 
  op.id, store.name, product.name, product.brand, op.created, price, amount 
  from product_ops op
  join products product on product.id=op.product_id
  join stores store on store.id=op.store_id  
  where (product.name = '${product_name}' or product.name iLIKE '%${product_name}%')
order by op.created desc 
limit 5" --full

info "average price:"
$query "select 
    product.name, 
    product.brand, 
    round((1 * sum(price) / sum(amount)), 2) as unit 
  from product_ops op
  join products product on product.id=op.product_id
  join stores store on store.id=op.store_id  
  where (product.name = '${product_name}' or product.name iLIKE '%${product_name}%')
group by product.id 
order by max(op.created) desc 
limit 5" --full
