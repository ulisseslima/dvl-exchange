#!/bin/bash -e
# @installable
# adds a new fixed-income operation
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

if [[ $# -lt 1 ]]; then
  echo "e.g.:"
  echo "$(sh_name $ME) SANTANDER 677.60 BRL --date '2020-12-02'"
  echo "date defaults to now if not specified"
  exit 0
fi

institution="${1^^}"; require institution
shift
amount="$1";          require -nx amount
shift
currency="${1^^}";    require currency
shift

while test $# -gt 0
do
  case "$1" in
    --date|-d|--created)
      shift 
      created="$1"
      if [[ "$created" != *':'* ]]; then
        created="$created $(now.sh -t)"
      fi
    ;;
    -*) 
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac
  
  shift
done

[[ -z "$created" ]] && created="$(now.sh -dt)"

rate=1
if [[ "$currency" == USD ]]; then
  # TODO use PTAX último dia útil da primeira quinzena do mês anterior ao recebimento
  rate=$($MYDIR/scoop-rate.sh USD -x BRL --date "$created" | jq -r .rates.BRL)
  require rate
fi

id=$($query "insert into fixed_income (created, currency, institution, amount, rate)
  select '$created', '$currency', '$institution', $amount, $rate
  returning id
")

if [[ -n "$id" ]]; then
  info "success: $id"
  $MYDIR/select-fixed-income.sh
fi
