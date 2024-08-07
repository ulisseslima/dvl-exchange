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
  echo "e.g.:"
  echo "$(sh_name $ME) BUY 40 TICKER 677.60 USD --date '2020-12-02'"
  echo && echo "note: price is the total price (amount*units). you can use math expressions. e.g.:"
  echo "e.g.:"
  echo "$(sh_name $ME) BUY 40 TICKER '16.94*40' USD"
  echo "date defaults to now if not specified"
  exit 0
fi

kind="${1^^}";      require --in 'BUY SELL' kind
shift
amount="$1";        require -nx amount
shift
ticker="${1^^}";    require ticker
shift
price="$1";         require -nx price
shift
currency="${1^^}";  require currency
shift
simulation=false

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
    --tags|-t)
      shift
      tags="'${1^^}'"
    ;;
    --extra|-e)
      shift
      extra="'${1,,}'"
    ;;
    --institution|-i)
      shift
      inst="'${1^^}'"
    ;;
    --simulation|--sim)
      simulation=true
    ;;
    -*) 
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac
  
  shift
done

[[ -z "$created" ]] && created="$(now.sh -dt)"
[[ -z "$inst" ]] && inst=undefined

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
  exchange=$($MYDIR/scoop-rate.sh $asset_currency -x $currency | jq -r .response.rates.$currency)
  require exchange

  exchanged=$(op $price/$exchange)
  info "accept conversion of $price $currency to $exchanged ${asset_currency}?"
  read confirmation

  price=$exchanged
  currency=$asset_currency
fi

rate=1
if [[ "$currency" == USD ]]; then
  # TODO use PTAX último dia útil da primeira quinzena do mês anterior ao recebimento
  rate=$($MYDIR/scoop-rate.sh USD -x BRL --date "$created" | jq -r .rates.BRL)
  require rate
fi

institution=$($query "select id from institutions where id ilike '%$inst%' order by id limit 1")
if [[ -z "$institution" ]]; then
  info "new institution: $inst"
  $query "insert into institutions (id) values ('$inst')"
else
  info "institution: $institution"
fi

id=$($query "insert into asset_ops (kind, asset_id, amount, price, currency, created, institution, rate, simulation)
  select '$kind', $asset_id, $amount, $price, '$currency', '$created', '$institution', $rate, $simulation
  returning id
")

if [[ -n "$id" ]]; then
  info "success: $id"
  $query "select ticker.name, op.* 
    from asset_ops op 
    join assets a on a.id=op.asset_id 
    join tickers ticker on ticker.id=a.ticker_id 
    where op.id = $id 
    and simulation is $simulation" --full

  if [[ $simulation != true ]]; then
    if [[ "$kind" == BUY ]]; then
      $query "update assets set
        amount=amount+($amount),
        cost=cost+($price),
        value=0
        where id = $asset_id
      "
    else
      # NOTE: there's no way to subtract the exact price, after a SELL operation
      $query "update assets set
        amount=amount-($amount),
        cost=cost-($price),
        value=0
        where id = $asset_id
      "
    fi
  fi

  # TODO get current value and calculate today's value
  
  info "current position:"
  $query "select * from assets where id = $asset_id" --full
fi
