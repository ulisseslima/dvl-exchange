#!/bin/bash -e
# @installable
# monthly income (stable + extra) vs spending balance
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
  echo "$(basename $0): Failed at $lineno: '$msg'"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

psql=$MYDIR/psql.sh

today="now()::date"
this_month=$(now.sh -m); [[ "$this_month" == 0* ]] && this_month=${this_month:1:1}
kotoshi=$(now.sh -y)

start="($today - interval '1 month')"
end="$today"
carry_args=""

while test $# -gt 0
do
    case "$1" in
    --month|-m)
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
    --between)
        start="'$2'"
        end="'$3'"
        carry_args="$carry_args --between $2 $3"
        shift; shift
    ;;
    --all|-a)
        start="'1900-01-01'"
        end="CURRENT_TIMESTAMP"
        carry_args="$carry_args --all"
    ;;
    *)
        echo "$(basename $0) - bad option '$1'"
        exit 1
    ;;
    esac
    shift
done

interval="$start and $end"

actual_start=$($psql "select $start")
actual_end=$($psql "select $end")

rate=$($MYDIR/scoop-rate.sh USD -x BRL | jq -r .rates.BRL)
require rate

info -n "=================================================="
info "EARNINGS (stable + extra income) [$actual_start to $actual_end]"
info -n "=================================================="
$MYDIR/select-earnings.sh --active $carry_args

info -n "=================================================="
info "SPENDING by category [$actual_start to $actual_end]"
info -n "=================================================="
$MYDIR/select-products.sh --totals-only $carry_args

# Compute totals for balance summary
earnings_brl=$($psql "select coalesce(round(sum(
    case when currency = 'USD' then total * $rate else total end
  ), 2), 0)
  from earnings
  where created between $interval
  and source in ('stable-income', 'extra-income')
")

spending_brl=$($psql "select coalesce(round(sum(op.price), 2), 0)
  from product_ops op
  join products product on product.id = op.product_id
  join stores store on store.id = op.store_id
  where op.created between $interval
  and simulation is false
")

info -n "=================================================="
info "BALANCE SUMMARY (BRL, USD rate: $rate)"
info -n "=================================================="
info "  earnings : $earnings_brl"
info "  spending : $spending_brl"
info -n "  balance  :"
op.sh "$earnings_brl - $spending_brl"
