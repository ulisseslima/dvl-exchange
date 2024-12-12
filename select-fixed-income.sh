#!/bin/bash -e
# @installable
# select fixed-income operations
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

psql=$MYDIR/psql.sh

and="1=1"
ticker="2=2"
grouping="op.id"
order_by='max(op.created)'

start="(now()::date - interval '1 month')"
end="CURRENT_TIMESTAMP"

today="now()::date"
this_month=$(now.sh -m)
kotoshi=$(now.sh -y)
simulation=false
earnings=true

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
    --simulation|--sim)
        simulation=true
    ;;
    --currency|-c)
        shift
        and="$and and op.currency='${1^^}'"
    ;;
    --from|--institution|-i)
        shift
        institution="${1^^}"
        and="$and and op.institution='${institution}'"
    ;;
    --group-by|-g)
        shift
        grouping="$1"
    ;;
    --total-only)
        total_only=true
    ;;
    --earnings)
        shift
        earnings=$1
    ;;
    -*)
        echo "$(sh_name $ME) - bad option '$1'"
        exit 1
    ;;
    esac
    shift
done

interval="$start and $end"

info "fixed income ops between $($psql "select $start") and $($psql "select $end")"
query="select * 
from fixed_income op 
where op.created between $interval
and $and
group by $grouping
order by
  $order_by
"

$psql "$query" --full
debug "$query"

info -n  "aggregated (all-time):"
if [[ -n "$institution" ]]; then
    query="select 'cost' as type, sum(amount), max(institution) as institution
    from fixed_income
    where institution ilike '${institution}%'
    and created between $interval
    union
    select 'dividends' as type, sum(total), max(institution_id)
    from earnings
    where source = 'passive-income'
    and created between $interval
    and institution_id ilike '${institution}%'
    "
else
    query="select 'cost' as type, sum(amount) 
    from fixed_income
    where created between $interval
    union
    select 'dividends' as type, sum(total) 
    from earnings
    where source = 'passive-income'
    and created between $interval
    "
fi

$psql "$query" --full
debug "$query"

info -n "total:"
agg=$($psql "$query")
cost=$(echo "$agg" | head -1 | cut -d'|' -f2)
divs=$(echo "$agg" | tail -1 | cut -d'|' -f2)
echo "$(op.sh ${cost}+${divs})"
