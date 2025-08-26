#!/bin/bash -e
# @installable
# finds similar products
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
shift

limit=5

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
    --limit|-l)
      shift
      limit="$1"
    ;;
    *)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac

  shift
done

$psql "select * from similars('$product') limit $limit" --full