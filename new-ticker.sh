#!/bin/bash -e
# @installable
# adds a new ticker for snapshots
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

if [[ $# -lt 1 ]]; then
  info "e.g.: $(sh_name $ME) IVVB11.SA"
  exit 0
fi

ticker="${1^^}"
require ticker

public=${2:-true}

ticker_id=$($query "select id from tickers where name iLIKE '${ticker}%' limit 1")
if [[ -z "$ticker_id" ]]; then
  ticker_id=$($query "insert into tickers (name) values ('$ticker') returning id")
else
  info "ticker already exists"
fi

info "ticker id: $ticker_id"
