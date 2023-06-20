#!/bin/bash -e
# @installable
# simulates how much do you need of an asset to get the desired mrr
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

psql=$MYDIR/psql.sh

today="now()::date"
this_month=$(now.sh -m)
kotoshi=$(now.sh -y)
avg=12

while test $# -gt 0
do
    case "$1" in
    --want|--desired|--mrr)
        shift
        mrr="$1"
    ;;
    --ticker|-t)
        shift
        ticker="${1^^}"
    ;;
    --avg)
        shift
        avg="$1"
    ;;
    -*)
        echo "$0 - bad option '$1'"
    ;;
    esac
    shift
done

require mrr "--mrr: desired monthly recurring revenue"
require ticker

ticker_id=$($psql "select id from tickers where name like '${ticker}%' limit 1")

query="select round(sum(value)/$avg, 2) from (
    select d.value
    from dividends d
    where ticker_id = $ticker_id
    and d.created between now()-interval '$avg months' and now()
    order by d.created desc
    limit $avg
) q"

debug "$query"
avg_dividends=$($psql "$query")

if [[ -z "$avg_dividends" ]]; then
    info "no dividends found for $ticker#$ticker_id, please inform:"
    read avg_dividends
else
    info "$ticker - average monthly dividends based on the last $avg months earnings: \$${avg_dividends}"
fi

curr_price=$($psql "select price($ticker_id)")

required=$(op "($mrr/$avg_dividends)*$curr_price")
quantity=$(op "$required/$curr_price")
diff=$(diff_percentage $required $mrr)

echo "${quantity}=\$${required} (${diff}%)"
