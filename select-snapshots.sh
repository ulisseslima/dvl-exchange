#!/bin/bash -e
# @installable
# snapshots search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

##
# called on error
function failure() {
  local lineno=$1
  local msg=$2
  echo "$(basename $0): Failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

psql=$MYDIR/psql.sh

rate=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .rates.BRL)
[[ -z "$rate" ]] && rate=0

and="1=1"
ticker="2=2"
group_by="op.id, ticker.id"
order_by='max(op.created)'

start="(now()::date - interval '1 month')"
end="CURRENT_TIMESTAMP"

today="now()::date"
this_month=$(now.sh -m)
kotoshi=$(now.sh -y)

cols="op.created,
  max(op.id)||'/'||ticker.id \"snap/tick\",
  ticker.name,
  op.price as unit,
  op.price,op.currency,
  (case when op.currency = 'USD' then round((price*$rate),2)::text else '-' end) BRL
"

while test $# -gt 0
do
    case "$1" in
    --ticker|-t)
        shift
        # eg for many tickers: TICKER_A|TICKER_B...
        ticker="ticker.name ~* '$1'"
    ;;
    --where|-w)
        shift
        and="$1"
    ;;
    --today)
        start="$today"
        end="($today + interval '1 day')"
    ;;
    --week|-w)
        start="($today - interval '1 week')"
        end="$today"
    ;;
    --month|-m)
        if [[ -n "$2" && "$2" != "-"* ]]; then
            shift
            m=$1
            
            this_month_int=$(op.sh "${this_month}::int")
            month_int=$(op.sh "${m}::int")
            [[ $this_month_int -ge $month_int ]] && year=$kotoshi || year=$(($kotoshi-1))

            start="'$year-$m-01'"
            end="('$year-$m-01'::timestamp + interval '1 month')"
        else
            start="($today - interval '1 month')"
            end="$today"
        fi
    ;;
    --year|-y)
        if [[ -n "$2" && "$2" != "-"* ]]; then
            shift
            y=$1
            start="'$y-01-01'"
            end="('$y-01-01'::timestamp + interval '1 year')"
        else
            start="($today - interval '1 year')"
            end="$today"
        fi
    ;;
    --until|-u)
        shift
        cut=$1
        start="'1900-01-01'"
        end="'$1'"
    ;;
    --all|-a)
        start="'1900-01-01'"
        end="now()"
    ;;
    --order-by|-o)
        shift
        order_by="$1"
    ;;
    --currency|-c)
        shift
        and="$and and op.currency='${1^^}'"
    ;;
    --kind|-k)
        shift
        and="$and and ticker.kind='${1^^}'"
    ;;
    --buys)
        and="$and and op.kind='BUY'"
    ;;
    --sells)
        and="$and and op.kind='SELL'"
    ;;
    --group-by|-g)
        shift
        group_by="$1"
    ;;
    --group-by-month|--gm)
        cols="date_trunc('month', op.created) as month,
            min(op.price) as min,
            round(avg(op.price),2) as unit,
            max(op.price) as max
        "
        order_by="month"
        group_by="month"
    ;;
    -*)
        echo "$(sh_name $ME) - bad option '$1'"
        exit 1
    ;;
    esac
    shift
done

interval="$start and $end"

info "snapshots between $($psql "select $start") and $($psql "select $end")"
query="select
  $cols,
  'plot:unit'
from snapshots op
join tickers ticker on ticker.id=op.ticker_id
where op.created between $interval
and $and
and $ticker
group by $group_by
order by
  $order_by
"

$psql "$($MYDIR/plotter.sh "$query")" --full
