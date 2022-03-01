#!/bin/bash -e
# @installable
# converts a BRL value to USD
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

usd="$1"
require -nx usd "amount in USD"

if [[ $(nan.sh "$usd") == true ]]; then
    $query "select $usd"
fi

exchange=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .response.rates.BRL)
require exchange
info "rate: 1 USD = $exchange BRL"

$query "select round((($usd)*$exchange)::numeric, 2)"

$query "insert into snapshots
(ticker_id, price, currency) 
values 
((select id from tickers where name = 'USD-BRL' limit 1), $exchange, 'BRL')"