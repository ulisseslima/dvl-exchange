#!/bin/bash -e
# @installable
# creates a suggestion of how to spend a specified amount among tickers.
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

if [[ $# -lt 1 ]]; then
  info "e.g.: $(sh_name $ME) 5000 USD --tickers TICKER1 [TICKER2 ...]"
  info "note: if some of the tickers are in a different currency, cost is converted automatically"
  exit 0
fi

amount="$1"
require -nx amount
shift

currency="${1^^}"
require currency
shift

simulation=false
units=true

##
# called on error
function failure() {
  local lineno=$1
  local msg=$2
  echo "Failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

while test $# -gt 0
do
  case "$1" in
    # don't by fractions
    --fractions-ok)
      info "* using fractions"
      units=false
    ;;
    # simulation op
    --simulation|--sim)
      info "* simulation mode"
      simulation=true
    ;;
    --tickers|-t)
      shift

      ntickers=0
      while test $# -gt 0
      do
        if [[ "$1" == -* ]]; then
          break
        fi

        tickers="${1^^} $tickers"
        ntickers=$((ntickers+1))

        if [[ "$2" == -* ]]; then
          break
        else
          shift
        fi
      done
    ;;
    --tax)
      echo taxing
      shift
      tax=$1
    ;;
    *)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac

  [[ $# -gt 0 ]] && shift
done

require tickers
require ntickers

per=$(op $amount/$ntickers)

rate=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .rates.BRL)
require rate

info "$amount/$ntickers = $per $currency per ticker"

i=1
while read ticker
do
  if [[ -z "$ticker" ]]; then
    break
  fi

  price=$($MYDIR/price.sh $ticker | cut -d'|' -f1)
  if [[ -z "$price" ]]; then
    err "ticker not found: $ticker"
    exit 1
  fi

  echo "$i: $ticker (${price}) -> $(op ${per}/${price})"
  
  if [[ $simulation == true ]]; then
    $MYDIR/new-op.sh BUY "${per}/${price}" $ticker ${per} $currency --simulation
  fi

  ((i++))
done < <(echo "$tickers" | tr ' ' '\n')
