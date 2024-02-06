#!/bin/bash -e
# @installable
# adds a new product buy to keep track of inflation and control expenses
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

psql=$MYDIR/psql.sh

product="$1"
require product 'product line as it appears in the receipt'

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
    --currency|-c)
      shift
      currency="${1^^}"
    ;;
    --tags|-t)
      shift
      tags="${1^^}"
    ;;
    --hide)
      hide=true
    ;;
    --simulation|--sim)
      simulation=true
    ;;
    --store|-s)
      shift
      store="$1"
    ;;
    --amount|-a)
      shift
      amount="$1"
    ;;
    --price|-p)
      shift
      price="$1"
    ;;
    --brand|-b)
      shift
      product_brand="$1"
    ;;
    -*)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac

  shift
done

require created "[-d] date of purchase"

match=$($psql "select similar('$product')")

product_id=$(echo "$match" | cut -d'#' -f1)
product_name=$(echo "$match" | cut -d'#' -f2)
if [[ -z "$product_brand" ]]; then
  product_brand=$(echo "$match" | cut -d'#' -f3)
fi

last_op_store=$(echo "$match" | cut -d'#' -f4)
if [[ -n "$store" ]]; then
  last_op_store="$store"
fi

last_op_amount=$(echo "$match" | cut -d'#' -f5)
if [[ -n "$amount" ]]; then
  last_op_amount="$amount"
fi

last_op_price=$(echo "$match" | cut -d'#' -f6)
if [[ -n "$price" ]]; then
  last_op_price="$price"
fi

echo "last similar buy:"
echo "$match"

echo "confirm?"
echo "'$last_op_store' '$product_name' '$product_brand' $last_op_amount $last_op_price -d '$created'"
read confirmation

$MYDIR/new-product.sh "$last_op_store" "$product_name" "$product_brand" $last_op_amount $last_op_price -d "$created"
