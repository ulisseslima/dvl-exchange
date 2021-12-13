#!/bin/bash -e
# @installable
# list latest orders
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh
filter="${1}"

q="SELECT
  t.name, o.*
FROM assets a 
JOIN tickers t on t.id=a.ticker_id 
JOIN asset_ops o on o.asset_id=a.id
WHERE 1=1
${filter}
ORDER BY t.name
"

$query "$q" --full
