#!/bin/bash -e
# @installable
# index search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

psql=$MYDIR/psql.sh

plot="'plot:price'"
dividends_tax=30

and="1=1"
ticker="2=2"
order_by='max(created)'

start="(now()::date - interval '1 month')"
end="CURRENT_TIMESTAMP"

today="now()::date"
this_month=$(now.sh -m)
kotoshi=$(now.sh -y)

cols="index_name,
max(created) as created,
sum(price) as price,
max(currency) as currency"

group_by="index_name"

while test $# -gt 0
do
    case "$1" in
    --index|-i)
        shift
        plot="'plot:price'"

        and="$and and index_name like '${1^^}%'"
        index_id=$($psql "select index_id from index_snapshots where index_name like '${1^^}%' limit 1")
        index_name=$($psql "select index_name from index_snapshots where index_name like '${1^^}%' limit 1")
    ;;
    --week|-w)
        start="($today - interval '1 week')"
        end="$today"
    ;;
    --month|-m)
        if [[ -n "$2" && "$2" != "-"* ]]; then
            shift
            m=$1

            [[ $(op_real "$this_month >= $m") == t ]] && year=$kotoshi || year=$(($kotoshi-1))

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
    --all|-a)
        start="'1900-01-01'"
        end="current_timestamp"
    ;;
    --group-by|-g)
        shift
        group_by="$1"
    ;;
    --plot)
        shift
        plot="${plot},
        'plot:$1'"
    ;;
    --order-by|-o)
        shift
        order_by="$1"
    ;;
    -*)
        echo "$(sh_name $ME) - bad option '$1'"
        exit 1
    ;;
    esac
    shift
done

interval="$start and $end"
info "indexes between $($psql "select $start") and $($psql "select $end"), grouping by $group_by"

filters="${and}"

query="select 
${cols},
${plot}
from index_snapshots
where created between $interval
and $filters
group by $group_by
order by
  $order_by
"
debug "query=$query"

$psql "$($MYDIR/plotter.sh "$query")" --full
