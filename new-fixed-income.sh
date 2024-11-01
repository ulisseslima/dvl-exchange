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
  echo "$(sh_name $ME) SANTANDER 500.00 --date '2020-01-05'"
  echo "date defaults to now if not specified"
  exit 0
fi

institution="${1^^}"; require institution
shift
amount="$1";          require -nx amount
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
    --recurring)
      shift
      recurring="$1"
    ;;
    -*)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac

  shift
done

[[ -z "$created" ]] && created="$(now.sh -dt)"

id=$($query "insert into fixed_income (created, institution, amount)
  select '$created', '$institution', $amount
  returning id
")

if [[ -n "$id" ]]; then
  info "success: $id"
  $MYDIR/select-fixed-income.sh
fi

if [[ $(nan.sh "$recurring") == false ]]; then
  info "scheduling new fixed-income op for $recurring months in the future:"
  next_recurrence=$(op.sh "('${created}'::date+interval '$recurring months')::date")
  >&2 echo "$next_recurrence"

  echo "$MYSELF '$institution' $amount -d $next_recurrence --recurring $recurring"\
   | at $next_recurrence
fi
