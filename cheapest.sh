#!/bin/bash -e
# @installable
# snapshot from todays' stock prices
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

fname=${1:---month}
case "$fname" in
    --today)
        filter='now()::date'
    ;;
    --week)
        filter="(now()::date - interval '1 week')"
    ;;
    --month)
        filter="(now()::date - interval '1 month')"
    ;;
    --year)
        filter="(now()::date - interval '1 year')"
    ;;
    --custom)
        shift
        filter="$1"
    ;;
    -*)
        echo "bad option '$1'"
    ;;
esac

info "$fname's snapshot, ordered by cheapest average price:"
$query "select
  ticker.name,
  max(snap.price), round(avg(snap.price)::numeric, 2) avg, min(snap.price),
  max(snap.currency) currency
from snapshots snap
join tickers ticker on ticker.id=snap.ticker_id
where snap.created > $filter
group by ticker.name
order by 
  max(snap.currency),
  avg(snap.price)
" --full