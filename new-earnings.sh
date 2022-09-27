#!/bin/bash -e
# @installable
# adds new earnings information
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

if [[ $# -lt 1 ]]; then
  sp=$(blanks $ME)
  info "usage example for hours worked:"
  info "$sp                       ┌[hours worked, or deliveries]"
  info "$ME Company 200.00 USD --amount 10"
  info "$sp             └[total received]"
  info "usage example for hourly rate:"
  info "$sp                       ┌[hourly rate]"
  info "$ME Company 200.00 USD --rate 20"
  info "$sp             └[total received]"
  exit 0
fi

institution="${1^^}"; require institution
shift
total="$1";           require -n total
shift
currency="$1";        require currency
shift

while test $# -gt 0
do
    case "$1" in
    --date|-d)
      shift 
      created="$1"
    ;;
    --amount|-a)
      shift
      amount="$1"
    ;;
    --rate|-r)
      shift
      rate="$1"
    ;;
    --full-time)
      amount=160
    ;;
    *) 
      echo "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

[[ -z "$created" ]] && created="$(now.sh -d)"

require --one amount rate
echo "amount: $amount - rate: $rate"

if [[ -n "$rate" ]]; then
  amount=$(echo "scale=2; $total/$rate" | bc)
  info "calculated amount (total/rate): $amount"
fi

institution_id=$($query "select id from institutions where id iLIKE '${institution}%' limit 1")
if [[ -z "$institution_id" ]]; then
  err "institution not found: '$institution'"
  
  info "insert?"
  read confirmation
  $query "insert into institutions (id) values ('$institution')"
fi

rate=1
if [[ "$currency" == USD ]]; then
  rate=$($MYDIR/scoop-rate.sh USD -x BRL --date "$created" | jq -r .response.rates.BRL)
  require rate
fi

info "'$institution_id', '$created', ($total/$amount), $amount, $total, '$currency', $rate"

id=$($query "insert into earnings (institution_id, created, value, amount, total, currency, rate)
  select '$institution_id', '$created', ($total/$amount), $amount, $total, '$currency', $rate
  returning id
")

if [[ -n "$id" ]]; then
  info "success: $id"
  $MYDIR/select-earnings.sh -t $institution --all
fi
