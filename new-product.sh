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

query=$MYDIR/psql.sh

if [[ $# -lt 1 ]]; then
  info "e.g.: $(sh_name $ME) WALMART 'ENERGY DRINK' 'RED BULL' 0.250 1.56 -x '*4' --date '2020-12-02'"
  exit 0
fi

store_name="${1^^}";      require --nan store_name; shift
product_name="${1^^}";    require --nan product_name; shift
# sanitize `product_name` to avoid SQL/shell parse issues
# replace ASCII double quote (") with right double quotation mark (U+201D)
product_name="${product_name//\"/”}"
# replace ASCII single quote (') with right single quotation mark (U+2019)
product_name="${product_name//\'/’}"
product_brand="${1^^}";   require --nan product_brand; shift
# input 0 to load the last amount purchased for this product
amount="$1";              require -nx amount; shift
price="$1";               require -nx price; shift
tags=null
hide=false
simulation=false
extra="'{}'"
background=false
schedule=true
recurring=null
installments=1

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
    --expression)
      shift
      expression="$1"
    ;;
    --tags|-t)
      shift
      tags="${1^^}"
    ;;
    --product-tags|-t)
      shift
      ptags="${1^^}"
    ;;
    --extra|-e)
      shift
      extra="'${1,,}'"
    ;;
    --carbs)
      shift
      extra="'{\"carbs\":$1}'"
    ;;
    --hide)
      hide=true
    ;;
    --simulation|--sim)
      simulation=true
    ;;
    --background|--bg)
      background=true
    ;;
    --recurring)
      shift
      recurring=$1
    ;;
    --no-scheduler)
      schedule=false
    ;;
    --installments|-x)
      shift
      installments=$1
    ;;
    *)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
  esac

  shift
done

[[ -z "$created" ]] && created="$(now.sh -dt)"

if [[ -n "$expression" ]]; then
  price=$(op.sh "${price} ${expression}")
  amount=$(op.sh "${amount} ${expression}")

  info "price: $price, amount: $amount"
fi

price=$(op.sh "round($price / $installments, 2)")
if [[ "$installments" -gt 1 ]]; then
  info "installments: $installments, cost per installment: $price"
fi

if [[ -n "$extra" ]]; then
  info "extra info: $extra"
fi

store_id=$($query "select id from stores where name = '${store_name}' or name iLIKE '%${store_name}%' limit 1")
if [[ -z "$store_id" ]]; then
  info "creating new store: $store_name"
  info "current categories:"
  $query "select
    count(category) n, category, (array_agg(name))[1:2] examples
    from stores
    group by category
    order by category
  " --full

  info "enter its category:"
  read category

  store_id=$($query "insert into stores (name, category) values ('$store_name', '${category^^}') returning id")
  echo "#$store_id"
fi

product_id=$($query "select id from products where (name = '${product_name}' or name iLIKE '%${product_name}%') and brand iLIKE '%${product_brand}%' order by name limit 1")
if [[ -z "$product_id" ]]; then
  info "creating new product: $product_name ($product_brand)"
  product_id=$($query "insert into products (name, brand, tags, extra, recurring) values ('$product_name', '$product_brand', '$ptags', $extra, $recurring) returning id")
  >&2 echo "#$product_id"
else
  original_product=$($query "select name, recurring from products where id = $product_id")
  recurring=$(echo "$original_product" | cut -d'|' -f2)

  info "updating product #$product_id: $original_product ($product_brand)"
  $query "update products set tags=tags || '$ptags', extra=extra || $extra where id = $product_id"
fi

if [[ $amount == 0 ]]; then
  amount=$($query "select amount from product_ops where product_id = $product_id order by id desc limit 1")
  if [[ -z "$amount" ]]; then
    err "no prior op for $product_name"
    exit 1
  fi
  info "using last amount: $amount"
fi

if [[ -z "$currency" ]]; then
  currency=$($query "select currency from product_ops where product_id = $product_id order by id desc limit 1")
  if [[ -z "$currency" ]]; then
    info "defaulting to $DEFAULT_CURRENCY for $product_name"
    currency=$DEFAULT_CURRENCY
  fi
  info "using last currency: $currency"
fi

# iterate over installments
for i in $(seq 1 $installments); do
  id=$($query "insert into product_ops (store_id, product_id, amount, price, currency, created, hidden, simulation, tags, installment)
    select $store_id, $product_id, $amount, $price, '$currency', '$created', $hide, $simulation, '$tags', $i
    returning id
  ")

  if [[ $installments != 1 ]]; then
    created=$(op.sh "('${created}'::date+interval '1 month')::date")
  fi
done

if [[ $schedule == true && $(nan.sh "$recurring") == false ]]; then
  info "[$created] scheduling new $product_name op for $recurring months in the future..."
  next_recurrence=$(op.sh "('${created}'::date+interval '$recurring months')::date")
  >&2 echo "$next_recurrence"

  if [[ $(op.sh "'$next_recurrence' < now()::date") != t ]]; then
    echo "$MYSELF '$store_name' '$product_name' '$product_brand' $amount $price -d $next_recurrence --background"\
    | at $next_recurrence
    
    [[ $background == false ]] && atq
  else
    info "skipping schedule for the past"
  fi
fi

if [[ "$background" == true ]]; then
  notify.sh "bg ex #${id}: $product_name ($product_brand) - $price"
  exit 0
fi

if [[ -n "$id" ]]; then
  info "new product op: $id - $product_name ($product_brand)"

  info "total cost:"
  $query "select sum(price) from product_ops where product_id = $product_id"

  $MYDIR/product-summary.sh "$product_name" -b "$product_brand"
fi

