#!/bin/bash -e
# @installable
# current ticker price
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh
mode='--csv'

ticker="${1^^}"
require ticker
shift

while test $# -gt 0
do
  case "$1" in
    --full)
      mode='--full'
    ;;
    -*)
      echo "$0 - bad option '$1'"
    ;;
  esac
  shift
done

$query "select
  price(ticker.id),
  max(snap.currency) currency
from snapshots snap
join tickers ticker on ticker.id=snap.ticker_id
where ticker.name like '${ticker}%'
group by ticker.id
" $mode
