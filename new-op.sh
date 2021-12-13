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

kind="$1";      require --in 'BUY SELL' kind
amount="$2";    require -n amount
ticker="$3";    require ticker
price="$4";     require -n price
currency="$5";  require currency
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

asset_currency=$($query "select currency from assets where asset_id = $asset_id")
if [[ "$asset_currency" != "$currency" ]]; then
  err "operation does not asset currency: $currency <> $asset_currency"
  exit 1
fi

id=$($query "insert into asset_ops (kind, asset_id, amount, price, currency, created, institution)
  select '$kind', $asset_id, $amount, $price, '$currency', '$created', '$inst'
  returning id
")

if [[ -n "$id" ]]; then
  info success
  $query "select ticker.name, op.* from asset_ops op join assets a on a.id=op.asset_id join tickers ticker on ticker.id=a.ticker_id where op.id = $id" --full

  if [[ "$kind" == BUY ]]; then
    $query "update assets set 
      amount=amount+$amount, 
      cost=cost+($price*$amount) 
      where id = $asset_id
    "
  else
    # NOTE: there's no way to subtract the exact price, after a SELL operation
    $query "update assets set 
      amount=amount-$amount, 
      cost=cost-($price*$amount) 
      where id = $asset_id
    "
  fi

  info "total:"
  inline-java.sh "println($price*$amount);"
  
  info "current position:"
  $query "select * from assets where id = $asset_id" --full
fi

# TODO colocar os fundos nomad:
# 345.13+207.22+125.5 = 677.85
# criar uma tabela de portfolio, permitindo splittar por vários stocks, criar um script bulk, que já insere usando a estratégia de diversificação
# nomad adventurer %: TLT 25.3 ISTB 17.1 XAR 9.8 FDN 9 IEMG 8.9 XSD 8.2 SPTL 6.6 RCD 6 IHY 5 RYT 1.6 XLI 1.3 RTH 1.2

