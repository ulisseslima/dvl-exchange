#!/bin/bash -e
# @installable
# get info from tickers
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh
yfapi=$MYDIR/api-yahoo-finance.sh

# TODO yfapi limits queries to 10 tickers at a time, handle it
while test $# -gt 0
do
    case "$1" in
    --tickers) 
      shift
      tickers="$1"
    ;;
    -*)
      echo "$(sh_name $ME) - bad option '$1'"
    ;;
    esac
    shift
done

require tickers "tickers separated by commas"

response=$($yfapi GET "qu/quote/$tickers")
if [[ -z "$response" ]]; then
  err "no response"
  exit 9
fi

echo "$response"
