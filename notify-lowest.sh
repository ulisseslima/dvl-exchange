#!/bin/bash -e
# @installable
# Notify tickers currently at their historical lowest price
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh

psql=$MYDIR/psql.sh

# default filter: last month (can be overridden by flags)
filter="(now()::date - interval '1 month')"

# default blacklist (comma-separated)
default_blacklist="SLED3.SA,USD-BRL,PSMB,ETH-USD,NUTX,YOLO,BAT-USD,DOGE-USD,BOVA11.SA,SMAL11.SA,MGLU3.SA,HASH11.SA,OIBR3.SA"
blacklist="$default_blacklist"

while test $# -gt 0
do
  case "$1" in
    --today|-t)
      filter='now()::date'
    ;;
    --week|-w)
      filter="(now()::date - interval '1 week')"
    ;;
    --month|-m)
      filter="(now()::date - interval '1 month')"
    ;;
    --year|-y)
      filter="(now()::date - interval '1 year')"
    ;;
    --blacklist)
      shift
      blacklist="$1"
    ;;
    *)
      echo "$(basename $0) - bad option '$1'"
      exit 1
    ;;
  esac
  shift
done

query="select
  ticker.name,
  price(ticker.id) as now_price,
  min(snap.price) as min_price,
  max(snap.currency) as currency
from tickers ticker
join snapshots snap on snap.ticker_id = ticker.id
where snap.created > $filter
  "

# build blacklist sql
blacklist_sql=""
if [[ -n "${blacklist// /}" ]]; then
  IFS=',' read -ra _bl <<< "$blacklist"
  items=()
  for b in "${_bl[@]}"; do
    bb=$(echo "$b" | xargs)
    # escape single quotes for SQL literals by doubling them
    bb=${bb//\'/\'\'}
    items+=("'$bb'")
  done
  blacklist_sql="and ticker.name not in ($(IFS=,; echo "${items[*]}"))"
fi

query+=" $blacklist_sql
group by ticker.id
having price(ticker.id) <= min(snap.price)
order by currency, ticker.name;"

info "Querying tickers whose current price is at (or below) historical min..."

result=$($psql "$query")

if [[ -z "$(echo "$result" | tr -d '[:space:]')" ]]; then
  info "No tickers found at historical lows."
  exit 0
fi

if command -v notify-send >/dev/null 2>&1; then
  notify_cmd="notify-send"
else
  notify_cmd="echo"
fi

while IFS="|" read -r name now_price min_price currency; do
  body="now: $now_price — min: $min_price $currency"
  if [[ "$notify_cmd" == "notify-send" ]]; then
    notify-send "Lowest price: $name" "$body"
    info "Sent notification for $name: $body"
  else
    echo "LOWEST: $name - $body"
  fi
done <<< "$result"

exit 0
