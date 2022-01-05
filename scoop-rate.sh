#!/bin/bash -e
# @installable
# get exchange rate for two currencies
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh
api=$MYDIR/currency-scoop-api.sh

currency="$1"
mode=latest

require currency

while test $# -gt 0
do
    case "$1" in
    -x) 
      shift
      symbols="$1"
    ;;
    --date)
      shift
      date="$1"
      mode=historical
    ;;
    -*)
      echo "bad option '$1'"
    ;;
    esac
    shift
done

require symbols

response=$($api GET "v1/$mode?base=$currency&symbols=$symbols&date=$date")
if [[ -z "$response" ]]; then
  err "no response"
  exit 9
fi

echo "$response"
