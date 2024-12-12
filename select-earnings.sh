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

##
# called on error
function failure() {
  local lineno=$1
  local msg=$2
  echo "Failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

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
    --institution|-t|--from)
        shift
        institution="institution.id ilike '$1%'"
    ;;
    --passive)
        and="$and and source = 'passive-income'"
    ;;
    --dividends)
        and="$and and source = 'passive-income'"
        include_dividends=true
    ;;
    --stable)
        and="$and and source = 'stable-income'"
    ;;
    --extra)
        and="$and and source = 'extra-income'"
    ;;
    --active)
        and="$and and source in ('stable-income', 'extra-income')"
    ;;
    --today)
        start="$today"
        end="($today + interval '1 day')"
        carry_args="$carry_args --today"
    ;;
    --week|-w)
        start="($today - interval '1 week')"
        end="$today"
        carry_args="$carry_args --week"
    ;;
    --month|-m)
        # kotoshi=今年
        if [[ -n "$2" && "$2" != "-"* ]]; then
            shift
            m=$1

            carry_args="$carry_args --month $m"

            this_month_int=$(op.sh "${this_month}::int")
            month_int=$(op.sh "${m}::int")
            [[ $this_month_int -ge $month_int ]] && year=$kotoshi || year=$(($kotoshi-1))

            start="'$year-$m-01'"
            end="('$year-$m-01'::timestamp + interval '1 month')"
        else
            start="($today - interval '1 month')"
            end="$today"

            carry_args="$carry_args --month"
        fi
    ;;
    --year|-y)
        if [[ -n "$2" && "$2" != "-"* ]]; then
            shift
            y=$1

            carry_args="$carry_args --year $y"

            start="'$y-01-01'"
            end="('$y-01-01'::timestamp + interval '1 year')"
        else
            start="($today - interval '1 year')"
            end="($today + interval '1 day')"

            carry_args="$carry_args --year"
        fi
    ;;
    --years)
        shift
        n=$1

        carry_args="$carry_args --years $n"
        
        d1="$today"
        start="($d1 - interval '$n years')"
        end="($d1 + interval '1 day')"
    ;;
    --months)
        shift
        n=$1

        carry_args="$carry_args --months $n"

        d1="$today"
        if [[ -n "$2" && "$2" != -* ]]; then
            shift
            d1="'$1'::date"
        fi

        start="($d1 - interval '$n months')"
        end="($d1 + interval '1 day')"
    ;;
    --all|-a)
        start="'1900-01-01'"
        end="CURRENT_TIMESTAMP"

        carry_args="$carry_args --all"
    ;;
    --order-by|-o)
        shift
        order_by="$1"
    ;;
    -*)
        echo "$0 - bad option '$1'"
        exit 1
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

if [[ "$include_dividends" == true ]]; then
    info "dividends, same period"
    $MYDIR/select-dividends.sh $carry_args
fi