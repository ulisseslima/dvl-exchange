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

date=$(now.sh -dt)

while test $# -gt 0
do
  case "$1" in
    --full)
      mode='--full'
    ;;
    --date|-d)
      shift
      date="$1"
    ;;
    -*)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac
  shift
done

info "date: $date"
$query "select
  snap.price,
  snap.currency
from snapshots snap
join tickers ticker on ticker.id=snap.ticker_id
where ticker.name like '${ticker}%'
and snap.created::date <= '$date'::date
group by ticker.id, snap.id
order by snap.created desc
limit 1
" $mode
