#!/bin/bash -e
# @installable
# deletes the last product op, or the one you specify
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
  id=$($query "select id from product_ops order by id desc limit 1")
fi

info "will delete op #$id, confirm?"
read confirmation

$query "delete from product_ops where id = $id"