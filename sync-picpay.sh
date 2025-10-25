#!/bin/bash -e
# @installable
# sync with PicPay's API
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)
source $MYDIR/db.sh

API=PicPay
query=$MYDIR/psql.sh

start=$($query "select date_trunc('day',created)::date from dividends where currency = 'BRL' order by created desc limit 1")
limit=$(dop "(now() - interval '2 days')::date")

end=$(dop "('$start'::date + interval '30 days')::date")
if [[ $(dop "'$end' > now()") == t ]]; then
  end="$limit"
fi

rate=1.02
date=$(now.sh -d)

month=$(echo "$date" | cut -d'-' -f2)
previous_month=$(op.sh ${month}-1)
cdi_mes=$(dvlx-br-indexes cdi -m $previous_month | cut -d '%' -f1)
rate_cdi=$(op.sh $cdi_mes*$rate)

while test $# -gt 0
do
  case "$1" in
    --start)
      shift
      start="${1}"
    ;;
    --end)
      shift
      end="$1"
    ;;
    *)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac

  shift
done

info "updating with $API ... date range: $start to $end"
# \[\{%22addons%22:\[\],%22id%22:%22PERIOD%22,%22values%22:\[%22LAST_90_DAYS%22\]\}\]
filter=$(echo '\[\{"addons":\[\],"id":"PERIOD","values":\["LAST_90_DAYS"\]\}\]' | urlencode.sh)
response=$($MYDIR/api-picpay.sh GET "account/statement/movements" "limit=50&page=1&activities=ALL&filters=$filter")
echo "$response"

if [[ -z "$response" ]]; then
    err "no response from $API, check token"
    exit 1
fi

if [[ "$response" == not-authorized ]]; then
    err "logged out. you need to update key info in $LOCAL_ENV"

    prompt_conf PICPAY_KEY "$API cookie contents"
    exit 7
fi

# node $MYDIR/process-sync-picpay.js "$response" $rate_cdi
# debug "node: $?/$!"

info "done"
