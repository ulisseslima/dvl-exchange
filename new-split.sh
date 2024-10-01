#!/bin/bash -e
# @installable
# registers a [reverse] split
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

if [[ $# -lt 1 ]]; then
  echo "e.g.:"
  echo "$(sh_name $ME) TICKER new_amount"
  echo "if new amount < current amount then reverse split"
  exit 0
fi

ticker=$1
require ticker
shift

new_amount=$1
require -n new_amount
shift

while test $# -gt 0
do
  case "$1" in
    --date|-d|--created)
      shift 
      created="$1"
      if [[ "$created" != *':'* ]]; then
        created="$created $(now.sh -t)"
      fi
    ;;
    -*) 
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac
  
  shift
done

[[ -z "$created" ]] && created="$(now.sh -dt)"

ticker_id=$($query "select id from tickers where name iLIKE '${ticker}%' limit 1")
if [[ -z "$ticker_id" ]]; then
  err "ticker not found: $ticker"
  exit 1
fi

asset_id=$($query "select id from assets where ticker_id = $ticker_id")
if [[ -z "$asset_id" ]]; then
  err "asset not found for ticker: $ticker"
  exit 2
fi

amount=$($query "select amount from assets where id = $asset_id")
if [[ $(op.sh "${amount} = ${new_amount}") == t ]]; then
	err "	└ reverse split already saved for ${ticker}#$asset_id = $amount"
  exit 0
fi
info "current amount: ${amount}"

reverse=false
if [[ $(op.sh "${amount}>${new_amount}") == t ]]; then
  reverse=true
  info "(reverse split)"
fi

$query "update assets set amount=$new_amount where id=$asset_id"
info " └- reverse split applied"

$query "insert into splits 
  (asset_id, ticker_id, old_amount, new_amount, reverse) 
values ($asset_id, $ticker_id, $amount, $new_amount, $reverse)
"

if [[ $reverse == true ]]; then
  op_amount=$(op.sh "-($amount-$new_amount)")
else
  op_amount=$(op.sh "${new_amount}-$amount")
fi

id=$($query "insert into asset_ops 
  (asset_id,kind,amount,price,currency,simulation) 
values ($asset_id, 'SPLIT', $op_amount, 0, 'BRL', false)
")
