#!/bin/bash -e
# @installable
# adds a new BUY/SELL simulated operation
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh
created="$(now.sh -dt)"

if [[ $# -lt 1 ]]; then
  echo "e.g.:"
  echo "$(sh_name $ME) BUY TICKER 677.60 USD --date '2020-12-02'"
  echo && echo "note: the value is the total price. the amount will be decided based on the last price registered for the date"
  echo "date defaults to now if not specified"
  exit 0
fi

kind="${1^^}";      require --in 'BUY SELL' kind
shift
ticker="${1^^}";    require ticker
shift
price="$1";         require -nx price
shift
currency="${1^^}";  require currency
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

unit_price=$($MYDIR/price.sh $ticker -d "$created" | cut -d'|' -f1)
amount=$(op.sh $price/$unit_price)

info "you'd get $amount units for $price $currency in $created"
$MYDIR/new-op.sh $kind $amount $ticker $price $currency -d "$created" --sim