#!/bin/bash -e
# @installable
# earnings search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

psql=$MYDIR/psql.sh

and="1=1"
institution="2=2"
order_by='op.created'

start="(now()::date - interval '1 month')"
end="CURRENT_TIMESTAMP"

today="now()::date"
this_month=$(now.sh -m); [[ "$this_month" == 0* ]] && this_month=${this_month:1:1}
kotoshi=$(now.sh -y)

limit=1000

function agg() {
    column=$(echo "$1" | cut -d' ' -f1)
    direction=$(echo "$1" | cut -d' ' -f2)

    echo "max($column) $direction"
}

while test $# -gt 0
do
    case "$1" in
    --where)
        shift
        and="$1"
    ;;
    --institution|-t|--from)
        shift
        institution="institution.id ilike '$1%'"
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
        # kotoshi=今年
        if [[ -n "$2" && "$2" != "-"* ]]; then
            shift
            m=$1

            [[ $this_month -ge $m ]] && year=$kotoshi || year=$(($kotoshi-1))

            start="'$year-$m-01'"
            end="('$year-$m-01'::timestamp + interval '1 month')"
        else
            start="($today - interval '1 month')"
            end="$today"
        fi
    ;;
    --year|-y)
        if [[ "$2" != "-"* ]]; then
            shift
            y=$1
            start="'$y-01-01'"
            end="('$y-01-01'::timestamp + interval '1 year')"
        else
            start="($today - interval '1 year')"
            end="$today"
        fi
    ;;
    --years)
        shift
        n=$1
        
        d1="$today"
        if [[ -n "$2" && "$2" != -* ]]; then
            shift
            d1="'$1'::date"
        fi

        start="($d1 - interval '$n years')"
        end="$d1"
    ;;
    --months)
        shift
        n=$1

        d1="$today"
        if [[ -n "$2" && "$2" != -* ]]; then
            shift
            d1="'$1'::date"
        fi

        start="($d1 - interval '$n months')"
        end="$d1"
    ;;
    --until)
        shift
        cut=$1
        start="'1900-01-01'"
        and="'$1'"
    ;;
    --all|-a)
        start="'1900-01-01'"
        end="CURRENT_TIMESTAMP"
    ;;
    --limit|--last)
        shift
        limit=$1

        start="'1900-01-01'"
        end="CURRENT_TIMESTAMP"
        order_by='op.created desc'
    ;;
    --order-by|-o)
        shift
        order_by="$1"
    ;;
    -*)
        echo "$0 - bad option '$1'"
    ;;
    esac
    shift
done

interval="$start and $end"

info "earnings between $($psql "select $start") and $($psql "select $end")"
query="select
  op.id,
  institution.id as institution,
  op.created,
  round(op.value, 2) as value,
  op.amount,
  op.total,
  op.currency,
  round(op.rate, 2) as rate,
  (case when op.currency = 'USD' then round((total*rate), 2)::text else total::text end) BRL,
  round(total/amount, 2) unit
from earnings op
join institutions institution on institution.id=op.institution_id
where op.created between $interval
and $and
and $institution
group by op.id, institution.id
order by $order_by
limit $limit
"

$psql "$query" --full

rate=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .rates.BRL)
require rate
info "today's rate: $rate"

info "aggregated sum [same value, different currencies]:"
query="select 
  round(sum(
    (case when op.currency = 'USD' then 
      (total*$rate) 
      else 
      total 
    end)
  ), 2) BRL,
  round(sum(
    (case when op.currency = 'BRL' then 
      (total/$rate) 
      else 
      total 
    end)
  ), 2) USD
from ($query) op
"
$psql "$query" --full
