#!/bin/bash -e
# @installable
# ops search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

filter="(now()::date - interval '1 month')"
and="1=1"
ticker="2=2"
while test $# -gt 0
do
    case "$1" in
    --where|-w)
        shift
        and="$1"
    ;;
    --ticker|-t)
        shift
        ticker="ticker.name ilike '$1%'"
    ;;
    --filter|-f)
        shift
        case "$1" in
            today)
                filter='now()::date'
            ;;
            week)
                filter="(now()::date - interval '1 week')"
            ;;
            month)
                filter="(now()::date - interval '1 month')"
            ;;
            year)
                filter="(now()::date - interval '1 year')"
            ;;
            none)
                filter="'2000-01-01'"
            ;;
        esac
    ;;
    --all|-a)
        filter="'2000-01-01'"
    ;;
    -*)
        echo "bad option '$1'"
    ;;
    esac
    shift
done

info "ops since '$($query "select $filter")'"
$query "select
  max(asset.id)||'/'||ticker.id \"ass/tick\",
  ticker.name,
  op.*
from asset_ops op
join assets asset on asset.id=op.asset_id
join tickers ticker on ticker.id=asset.ticker_id
where op.created > $filter
and $and
and $ticker
group by op.id, ticker.id
order by
  max(op.created) desc
" --full
