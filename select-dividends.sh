#!/bin/bash -e
# @installable
# dividends search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

psql=$MYDIR/psql.sh

dividends_tax=30

and="1=1"
ticker="2=2"
order_by='max(op.created)'

start="(now()::date - interval '1 month')"
end="CURRENT_TIMESTAMP"

today="now()::date"
this_month=$(now.sh -m)
kotoshi=$(now.sh -y)

cols="ticker.id,
  ticker.name,
  op.id as op_id,
  op.created,
  round(op.value, 2) as unit,
  op.amount,
  op.total,
  op.currency,
  round(op.rate, 2) as rate,
  (case when op.currency = 'USD' then round((total*rate), 2)::text else total::text end) BRL
"
group_by="op.id, ticker.id"

while test $# -gt 0
do
    case "$1" in
    --where)
        shift
        and="$1"
    ;;
    --ticker|-t)
        shift
        ticker="ticker.name ilike '$1%'"
        ticker_id=$($psql "select id from tickers where name ilike '${1}%' limit 1")
        ticker_name=$($psql "select name from tickers where name ilike '${1}%' limit 1")
    ;;
    --currency|-c)
        shift
        clause="${1^^}"
        and="$and and op.currency='$clause'"
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

            [[ $(op_real "$this_month >= $m") == t ]] && year=$kotoshi || year=$(($kotoshi-1))

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
    --until)
        shift
        cut=$1
        start="'1900-01-01'"
        and="'$1'"
    ;;
    --all|-a)
        start="'1900-01-01'"
        end="current_timestamp"
    ;;
    --group-by|-g)
        shift
        group_by="$1"
    ;;
    --group-by-ticker|--gt)
        cols="ticker.id,
            ticker.name,
            round(avg(op.value), 2) as unit,
            sum(op.amount) as shares,
            sum(op.total) as total,
            ticker.currency,
            (case when ticker.currency = 'USD' then round((sum(op.total)*avg(op.rate)), 2)::text else sum(op.total)::text end) BRL
        "
        order_by="ticker.currency, total desc"
        group_by="ticker.id"
    ;;
    --group-by-month|--gm)
        cols="date_part('month', op.created) as month,
            round(avg(op.value), 2) as unit,
            sum(op.amount) as shares,
            sum(op.total) as total,
            array_agg(distinct ticker.currency) currencies,
            round(avg(op.rate), 3) avg_rate,
            round(sum(op.total*op.rate), 2) as brl
        "
        order_by="month"
        group_by="month"
    ;;
    --select)
        shift
        cols="$cols,$1"
    ;;
    --order-by|-o)
        shift
        order_by="$1"
    ;;
    -*)
        echo "$(sh_name $ME) - bad option '$1'"
    ;;
    esac
    shift
done

interval="$start and $end"
info "dividends between $($psql "select $start") and $($psql "select $end")"

filters="$and and $ticker"

query="select $cols
from dividends op
join tickers ticker on ticker.id=op.ticker_id
where op.created between $interval
and $filters
group by $group_by
order by
  $order_by
"
debug "query=$query"

$psql "$query" --full

if [[ "$group_by" == "month" ]]; then
    info "aggregated sum:"
    $psql "select
    round(sum(total), 2) as USD,
    round(sum(brl), 2) as BRL,
    percentage(sum(brl), $dividends_tax) as taxes
    from ($query) op
    " --full
else
    rate=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .rates.BRL)
    require rate
    info "today's rate: $rate"

    info "aggregated sum [same value, different currencies]:"
    $psql "select
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
    " --full
fi

avg=12
if [[ -n "$ticker_id" ]]; then
    div_pm_query="select round(sum(total)/$avg, 2) from (
        select op.total
        from dividends op
        join tickers ticker on ticker.id=op.ticker_id
        where op.created between now()-interval '$avg months' and now()
        and $filters
        order by op.created desc
    ) q"

    debug "$div_pm_query"
    avg_dividends=$($psql "$div_pm_query")

    if [[ -n "$avg_dividends" ]]; then
        info "$ticker_name - average monthly dividends based on the last $avg months earnings: \$${avg_dividends}"
    fi
else
    div_pm_query="select (round(sum(total)/$avg, 2)), currency from (
        select op.total, op.currency
        from dividends op
        join tickers ticker on ticker.id=op.ticker_id
        where op.created between now()-interval '$avg months' and now()
        and $filters
        order by op.created desc
    ) q
    group by currency"

    debug "$div_pm_query"
    avg_dividends=$($psql "$div_pm_query")

    if [[ -n "$avg_dividends" ]]; then
        info "average monthly dividends based on the last $avg months earnings:"
        echo "${avg_dividends}"

        if [[ -n "$rate" ]]; then
            USD=$(echo "${avg_dividends}" | grep USD | cut -d'|' -f1)
            BRL=$(echo "${avg_dividends}" | grep BRL | cut -d'|' -f1)
            ALL_TO_BRL=$(op "$BRL+($USD*$rate)")
            echo "=$ALL_TO_BRL BRL"
        fi
    fi
fi