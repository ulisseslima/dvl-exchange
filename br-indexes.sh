#!/bin/bash
# @installable
# show common indexes in month's values
# e.g.:
# $0 CDI --start 2024-07-05 --end 2025-01-05 # accumulated CDI during period
# applying it on a value of 100:
# $0 CDI --start 2024-07-05 --end 2025-01-05 | percent.sh 100 --op '+'
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

# bcb time series (month)
# https://api.bcb.gov.br/dados/serie/bcdata.sgs.${index_id}/dados?formato=json&dataInicial=dd/MM/yyyy&dataFinal=dd/MM/yyyy
#* CDI do dia: 12
#* https://dadosabertos.bcb.gov.br/dataset/20542-saldo-da-carteira-de-credito-com-recursos-livres---total/resource/6e2b0c97-afab-4790-b8aa-b9542923cf88

# bacen API
# * https://dadosabertos.bcb.gov.br/

# todos índices
# * https://www.melhorcambio.com/tr

# TODO create indexes table to follow
# https://www.portalbrasil.net/igpm/

# calc:
# https://www3.bcb.gov.br/CALCIDADAO/publico/exibirFormCorrecaoValores.do?method=exibirFormCorrecaoValores

# TR - taxa referencial (usada como base pra poupança). divulgado todo dia pelo bacen
# * http://www.yahii.com.br/tr.html

function now_br() {
  date +"%d/%m/%Y"
}

function dop_br() {
  date="$1"
  debug "converting '$date' to date..."
  if [[ "$date" =~ ^[0-9] ]]; then
    # if it starts with a number, it's a literal date
    $query "select to_char('$1'::date, 'dd/mm/yyyy')"
  else
    # otherwise, it's an expression
    $query "select to_char($1, 'dd/mm/yyyy')"
  fi
}

api=$MYDIR/api-bcb.sh

today="now()::date"
this_month=$(now.sh -m)
kotoshi=$(now.sh -y)
day_one_otm="${kotoshi}-${this_month}-01"

# taxa referencial (poupança)
TR=7811
CDI=4391
IGPM=189
IPCA=433
SELIC=4390

index=${1^^}
require index "arg1: index name"

index_id=${!index}
require index_id "index ID"

start="$today"
end="$today"

accumulate=true

while test $# -gt 0
do
    case "$1" in
    --start)
      shift
      start="$1"
    ;;
    --end)
      shift
      end="$1"
    ;;
    --month|-m)
      if [[ -n "$2" && "$2" != "-"* ]]; then
          shift
          m=$1
          [[ -z "$m" ]] && m=$(now.sh -m)

          this_month_int=$(op.sh "${this_month}::int")
          month_int=$(op.sh "${m}::int")
          [[ $this_month_int -ge $month_int ]] && year=$kotoshi || year=$(($kotoshi-1))

          start="'$year-$m-01'::timestamp"
          end="('$year-$m-01'::timestamp + interval '1 month')"
      else
          start="($today - interval '1 month')"
          end="$today"
      fi
      accumulate=false
    ;;
    --year|-y)
        if [[ -n "$2" && "$2" != "-"* ]]; then
            shift
            y=$1
            [[ -z "$y" ]] && y=$(now.sh -y)

            start="'$y-01-01'::timestamp"
            end="('$y-01-01'::timestamp + interval '1 year, -1 day')"
        else
            start="($today - interval '1 year, 1 day')"
            end="$today"
        fi
    ;;
    --accumulate|--last)
      shift
      n=$1

      if [[ -n "$2" && "$2" != "-"* ]]; then
          shift
          start="'$1'::date"
          info "considering start date as: $start"
      fi

      start="('$day_one_otm'::date - interval '$n months')"
      end="('$day_one_otm'::date)"
    ;;
    *)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

info "checking $index [#$index_id]
 - from $start to $end"

response=$($api GET "bcdata.sgs.${index_id}/dados" "dataInicial=$(dop_br "${start}")&dataFinal=$(dop_br "${end}")")
last_date=0
accumulated_price=0
while read item
do
  require item
  debug "got $index [$index_id]: $item"

  date=$(echo "$item" | jq -r .data)
  price=$(echo "$item" | jq -r .valor)

  info "date: $date, price: $price"

  if [[ -z "$date" || "$date" == "null" || -z "$price" || "$price" == "null" ]]; then
    err "no data for range: $start to $end [$index_id]"
    continue
  fi

  if [[ "$date" == "$last_date" ]]; then
    info "skipping dupe $date"
    continue
  fi
  last_date="$date"

  if [[ $accumulate == true ]]; then
    accumulated_price=$(op $accumulated_price+$price)
  else
    accumulated_price=$price
    $query "insert into index_snapshots (index_id, index_name, created, price, currency)
      SELECT $index_id, '$index', to_date('$date', 'DD/MM/YYYY'), $price, 'BRL'
      WHERE NOT EXISTS (select * from index_snapshots where index_name = '$index' and created = to_date('$date', 'DD/MM/YYYY'))
    "
    break
  fi

  last_price=$($query "select price from index_snapshots where index_id = $index_id and created = to_date('$date', 'DD/MM/YYYY')")
  if [[ -z "$last_price" ]]; then
    info "inserting $index [$index_id]: $item"

    $query "insert into index_snapshots (index_id, index_name, created, price, currency)
      SELECT $index_id, '$index', to_date('$date', 'DD/MM/YYYY'), $price, 'BRL'
    "
  elif [[ $last_price != $price ]]; then
    info "(updating from $last_price to $price)"
    $query "update index_snapshots
      set price=$price
      where index_id = $index_id and created = to_date('$date', 'DD/MM/YYYY')
    "
  fi
done < <(echo "$response" | jq -c '.[]')

echo "${accumulated_price}%"
