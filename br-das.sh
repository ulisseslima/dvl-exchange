#!/bin/bash -e
# @installable
# cálculo do DAS
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

psql=$MYDIR/psql.sh

# O cálculo consiste em encontrar a alíquota efetiva do recolhimento do mês atual.
# A fórmula para calcular a alíquota efetiva é a seguinte:
# [(RBT12 x ALIQ) - PD] ÷ RBT12
#
# RBT12 Receita Bruta dos últimos 12 meses
# ALIQ = Alíquota
# PD – Parcela a Deduzir

institution="$1"
require institution

earnings_query="select
  op.created,
  (case when op.currency = 'USD' then round((total*op.rate), 2)::text else total::text end) BRL
from earnings op
join institutions institution on institution.id=op.institution_id
where institution.id ilike '${institution}%'
group by op.id, institution.id
order by op.created desc
limit 12
"

table="$($psql "$earnings_query")"
require table

year_earnings=$($psql "select sum(brl::numeric) from ($earnings_query) as q")
require year_earnings
info "earning last 12 months: $year_earnings"

last_earning=$(echo "$table" | head -1 | cut -d'|' -f2)
require last_earning
info "last earning $last_earning BRL"

tax_info=$($psql "select tax, deduction from br_simples_nacional where cut >= $year_earnings order by cut limit 1")
tax=$(echo "$tax_info" | cut -d'|' -f1)
deduction=$(echo "$tax_info" | cut -d'|' -f2)

a=$(op "($year_earnings*$tax)/100")
b=$(op "$a-$deduction")
debug "b - $b/$year_earnings"
tax_percentage=$(op_real "$b/$year_earnings")

# note: percentage is rounded up for readability
# note: final value is rounded up, the real final tax is:
debug "real final tax: $(op_real ${tax_percentage}*100)%"

echo "final tax: $(op "${tax_percentage}*100")% ="
op "$last_earning*$tax_percentage"