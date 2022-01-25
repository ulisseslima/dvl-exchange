#!/bin/bash -e
# @installable
# assets search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

filter="'2000-01-01'"
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
  ticker.id ticker_id,
  ticker.name,
  asset.*
from assets asset
join tickers ticker on ticker.id=asset.ticker_id
where asset.created > $filter
and $and
and $ticker
group by ticker.id, asset.id
order by
  ticker.name
" --full
