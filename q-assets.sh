#!/bin/bash -e
# @installable
# lists current assets, TODO: calculate current value
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

filter="1=1"
order="t.name"

while test $# -gt 0
do
    case "$1" in
    --where) 
      shift
      filter="$1"
    ;;
    --order)
      shift
      order="$1"
    ;;
    -*) 
      echo "bad option '$1'"
    ;;
    esac
    shift
done

q="SELECT ticker.name,
  asset.id asset_id, asset.ticker_id, asset.amount, asset.cost
FROM assets asset
JOIN tickers ticker on ticker.id=asset.ticker_id 
WHERE ${filter}
ORDER BY $order
"

$query "$q" --full
