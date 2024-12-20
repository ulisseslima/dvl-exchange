#!/bin/bash -e
# @installable
# adds a new dividend value. NOTE: always include values BEFORE taxes.
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

if [[ $# -lt 1 ]]; then
  info "usage example:"
  echo "$ME AGG 2.41 $(now.sh -d)"
  exit 0
fi

ticker="${1^^}";  require ticker
total="$2";       require -n total
created="$3";     [[ -z "$created" ]] && created="$(now.sh -dt)"

ticker_id=$($query "select id from tickers where name iLIKE '${ticker}%' limit 1")
if [[ -z "$ticker_id" ]]; then
  err "ticker not found $ticker"
  exit 1
fi

asset_id=$($query "select id from assets where ticker_id = $ticker_id")
if [[ -z "$asset_id" ]]; then
  err "asset not found for $ticker"
  exit 1
fi

asset_currency=$($query "select currency from assets where id = $asset_id")

rate=1
if [[ "$asset_currency" == USD ]]; then
  # TODO use PTAX último dia útil da primeira quinzena do mês anterior ao recebimento
  rate=$($MYDIR/scoop-rate.sh USD -x BRL --date "$created" | jq -r .rates.BRL)
  require rate
fi

position=$($MYDIR/position.sh --until "$created" -t $ticker --short)
amount=$(echo "$position" | cut -d'|' -f3)
info "position: $position ($amount)"

info "$ticker_id, '$created', ($total/$amount), $amount, $total, '$asset_currency', $rate"

id=$($query "insert into dividends (ticker_id, created, value, amount, total, currency, rate)
  select $ticker_id, '$created', ($total/$amount), $amount, $total, '$asset_currency', $rate
  returning id
")

if [[ -n "$id" ]]; then
  info "success: $id"
  $MYDIR/select-dividends.sh -t $ticker --all
fi
