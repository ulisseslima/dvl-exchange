#!/bin/bash -e
# undoes the last insert in a table, or the id specified
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

table=$1
id="$2"
if [[ -z "$id" ]]; then
  id=$($query "select id from $table order by id desc limit 1")
fi

info "will delete $table #$id, confirm?"
read confirmation

$query "delete from $table where id = $id"