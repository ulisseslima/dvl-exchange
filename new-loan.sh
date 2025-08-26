#!/bin/bash -e
# @installable
# adds a new loan.
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
  echo "$ME TICKER 0.04 --shares 10 -d $(now.sh -d)"
  echo "" && echo "where 0.04 is the total earned, and 10 is the number of shares loaned."
  echo "if not specified, considers the current position amount for the ticker"
  exit 0
fi

ticker="${1^^}";  require ticker && shift
total="$1";       require -n total && shift

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
    --shares)
      shift
      amount="$1"
    ;;
    *)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac

  shift
done

[[ -z "$created" ]] && created="$(now.sh -dt)"

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

if [[ -z "$amount" ]]; then
  position=$($MYDIR/position.sh --until "$created" -t $ticker --short)
  amount=$(echo "$position" | cut -d'|' -f3)
fi

info "$ticker_id, '$created', ($total/$amount), $amount, $total, '$asset_currency', $rate"

id=$($query "insert into loans (ticker_id, created, amount, total, currency, rate)
  select $ticker_id, '$created', $amount, $total, '$asset_currency', $rate
  returning id
")

if [[ -n "$id" ]]; then
  info "success: $id"
  $MYDIR/select-loans.sh -t $ticker --all
fi
