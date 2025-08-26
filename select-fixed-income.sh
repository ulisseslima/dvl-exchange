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
cols="op.id,op.created,currency,institution_id,amount,notes"
join="join institutions i on op.institution_id = i.id"
grouping="op.id"
order_by='max(op.created)'

start="(now()::date - interval '1 month')"
end="CURRENT_TIMESTAMP"

today="now()::date"
this_month=$(now.sh -m)
kotoshi=$(now.sh -y)
simulation=false

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
        and="$and and op.institution_id like '${institution}%'"
    ;;
    --join)
        shift
        join="$1"
    ;;
    --union)
        shift
        union="$1"
    ;;
    --group-by|-g)
        shift
        grouping="$1"
    ;;
    --totals)
        totals=true
        
        cols="i.public_id,institution_id,sum(amount) as contribution"
        grouping="op.institution_id,i.id"
    ;;
    *)
        echo "$(sh_name $ME) - bad option '$1'"
        exit 1
    ;;
    esac
    shift
done

interval="$start and $end"

info "fixed income ops between $($psql "select $start") and $($psql "select $end")"
query="select ${cols}
 from fixed_income op 
 $join
 where op.created between $interval
 and $and
 $union
 group by ${grouping}
 order by ${order_by}
"

$psql "$query" --full
debug "$query"

info -n  "aggregated:"
if [[ "$totals" == true ]]; then
    query="select pubid, institution_id, sum(val) grand_total from (
        select 'cost' as type, amount as val, institution_id, i.public_id as pubid
        from fixed_income op
        $join
        where op.created between $interval
        and $and
        union all
        select 'dividends' as type, total as val, institution_id, i.public_id as pubid
        from earnings op
        $join
        where source = 'passive-income'
        and op.created between $interval
        and $and
    ) as totals 
    group by institution_id, pubid
    "
else
    query="select 'cost' as type, coalesce(sum(amount), 0) as total, array_agg(distinct institution_id) as institution_id
    from fixed_income op
    where created between $interval
    and $and
    union
    select 'dividends' as type, coalesce(sum(total), 0) as total, array_agg(distinct institution_id) as institution_id
    from earnings op
    where source = 'passive-income'
    and created between $interval
    and $and
    "
fi

$psql "$query" --full
debug "$query"

if [[ "$totals" != true ]]; then
    info -n "total:"
    agg=$($psql "$query")
    cost=$(echo "$agg" | head -1 | cut -d'|' -f2)
    divs=$(echo "$agg" | tail -1 | cut -d'|' -f2)
    [[ -z "$divs" ]] && divs=0
    [[ -z "$cost" ]] && cost=0

    echo "$(op.sh ${cost}+${divs})"
fi