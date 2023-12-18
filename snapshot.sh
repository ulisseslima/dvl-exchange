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
quote=$MYDIR/y-quote.sh

filter="$(now.sh -dt)"
info "$filter - updating old prices..."

function outdated_tickers() {
    $query "select ticker.name as tick 
        from tickers ticker 
        left join snapshots snapshot on snapshot.ticker_id=ticker.id 
        where public is true
        and snapshot is null
    union
        select ticker.name as tick
        from tickers ticker 
        join snapshots snapshot on snapshot.ticker_id=ticker.id 
        where public is true
        group by ticker.name
        having max(snapshot.created) < '$filter'
    order by tick
    limit 10
    ;" | tr '\n' ','
}

tickers="$(outdated_tickers)"
last_tickers="$tickers"
if [[ "$1" == test ]]; then
    echo "'$filter': $tickers"
    exit 0
fi

while [[ -n "$tickers" ]]; do
    info "filter: '$filter' - updating prices for $tickers ..."
    response=$($quote --tickers "$tickers")
    
    if [[ "$response" == *"Limit Exceeded"* ]]; then
        err "$response"
        exit 7
    fi
    
    node $MYDIR/process-quotes.js "$response"
    debug "node: $?/$!"

    tickers="$(outdated_tickers)"
    if [[ "$tickers" == "$last_tickers" ]]; then
        err "tickers didn't change"
        exit 8
    else
        last_tickers="$tickers"
    fi
done

info "done"
$MYDIR/cheapest.sh
