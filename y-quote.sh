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
yfapi=$MYDIR/yfapi.sh

# TODO yfapi limits queries to 10 tickers at a time, handle it
while test $# -gt 0
do
    case "$1" in
    --tickers) 
      shift
      tickers="$1"
    ;;
    -*)
      echo "bad option '$1'"
    ;;
    esac
    shift
done

require tickers

response=$($yfapi GET "v6/finance/quote?symbols=$tickers")
if [[ -z "$response" ]]; then
  err "no response"
  exit 9
fi

echo "$response"
