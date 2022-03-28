#!/bin/bash -e
# @installable
# adds a new BUY/SELL operation
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

if [[ $# -lt 1 ]]; then
  info "e.g.: $0 BUY 40 TICKER 677.85 USD '2020-12-02'"
  exit 0
fi

kind="${1^^}";      require --in 'BUY SELL' kind
amount="$2";    require -n amount
ticker="${3^^}";    require ticker
price="$4";     require -n price
currency="${5^^}";  require currency
created="$6";   [[ -z "$created" ]] && created=$(now.sh -d)
inst="$7";      [[ -z "$inst" ]] && inst=undefined

ticker_id=$($query "select id from tickers where name iLIKE '${ticker}%' limit 1")
if [[ -z "$ticker_id" ]]; then
  ticker_id=$($query "insert into tickers (name) values ('$ticker') returning id")
fi

asset_id=$($query "select id from assets where ticker_id = $ticker_id")
if [[ -z "$asset_id" ]]; then
  info "creating new asset"
  asset_id=$($query "insert into assets (ticker_id, currency) values ($ticker_id, '$currency') returning id")
fi

asset_currency=$($query "select currency from assets where id = $asset_id")
if [[ "$asset_currency" != "$currency" ]]; then
  err "operation does not match asset currency: $currency <> $asset_currency"
  exit 4
fi

rate=1
if [[ "$currency" == USD ]]; then
  rate=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .response.rates.BRL)
  require rate
fi

institution=$($query "select id from institutions where id ilike '%$inst%' order by id limit 1")
if [[ -z "$institution" ]]; then
  info "new institution: $inst"
  $query "insert into institutions (id) values ('$inst')"
else
  info "institution: $institution"
fi

id=$($query "insert into asset_ops (kind, asset_id, amount, price, currency, created, institution, rate)
  select '$kind', $asset_id, $amount, $price, '$currency', '$created', '$institution', $rate
  returning id
")

if [[ -n "$id" ]]; then
  info "success: $id"
  $query "select ticker.name, op.* from asset_ops op join assets a on a.id=op.asset_id join tickers ticker on ticker.id=a.ticker_id where op.id = $id" --full

  if [[ "$kind" == BUY ]]; then
    $query "update assets set
      amount=amount+$amount,
      cost=cost+($price*$amount),
      value=0
      where id = $asset_id
    "
  else
    # NOTE: there's no way to subtract the exact price, after a SELL operation
    $query "update assets set
      amount=amount-$amount,
      cost=cost-($price*$amount),
      value=0
      where id = $asset_id
    "
  fi

  info "total cost:"
  inline-java.sh "println($price*$amount);"

  # TODO get current value and calculate today's value
  
  info "current position:"
  $query "select * from assets where id = $asset_id" --full
fi
