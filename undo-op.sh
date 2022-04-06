#!/bin/bash -e
# @installable
# deletes an asset_op
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

id="$1"
if [[ -z "$id" ]]; then
  id=$($query "select id from asset_ops order by id desc limit 1")
fi

amount=$($query "select amount from asset_ops where id = $id")
price=$($query "select price from asset_ops where id = $id")
asset_id=$($query "select asset_id from asset_ops where id = $id")

if [[ -z "$asset_id" ]]; then
  err "asset op with asset #$asset_id not found"
  exit 1
fi

info "will delete op #$id {price: $price, amount: $amount}, confirm?"
read confirmation

$query "delete from asset_ops where id = $id"
$query "update assets set amount = amount - $amount, cost = cost - $price where id = $asset_id"