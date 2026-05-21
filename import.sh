#!/bin/bash -e
# @installable
# batch-imports products from a TSV receipt table into quick-product.sh
# expected columns (tab-separated): Nome do Produto  Quantidade  Valor  Total
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

created="$(now.sh -dt)"
input_file=""
store=""
currency=""

while test $# -gt 0
do
  case "$1" in
    --date|-d|--created)
      shift
      created="$1"
      if [[ "$created" == now ]]; then
        created="$(now.sh -dt)"
      fi
      if [[ "$created" != *':'* ]]; then
        created="$created $(now.sh -t)"
      fi
    ;;
    --store|-s)
      shift
      store="$1"
    ;;
    --currency|-c)
      shift
      currency="${1^^}"
    ;;
    --file|-f)
      shift
      input_file="$1"
    ;;
    -*)
      echo "$(sh_name $ME) - bad option '$1'"
      exit 1
    ;;
    *)
      input_file="$1"
    ;;
  esac
  shift
done

if [[ -n "$input_file" ]]; then
  exec < "$input_file"
fi

# skip header line
read -r header

while IFS=$'\t' read -r product_name quantity price total; do
  [[ -z "$product_name" ]] && continue

  # strip "R$ " prefix (with or without space) and convert Brazilian decimal comma to period
  price=$(echo "$price" | sed 's/R\$[[:space:]]*//' | tr ',' '.')

  # strip leading/trailing whitespace from quantity
  quantity="${quantity// /}"

  # extract weight/volume from product name: NNNkg → NNN, NNNg → NNN/1000, NNNML → NNN/1000, NNNL → NNN
  weight=""
  if [[ "$product_name" =~ ([0-9]+)KG ]]; then
    weight=$(awk "BEGIN { printf \"%.3f\", ${BASH_REMATCH[1]} }")
  elif [[ "$product_name" =~ ([0-9]+)ML ]]; then
    weight=$(awk "BEGIN { printf \"%.3f\", ${BASH_REMATCH[1]} / 1000 }")
  elif [[ "$product_name" =~ ([0-9]+)G([^A-Z]|$) ]]; then
    weight=$(awk "BEGIN { printf \"%.3f\", ${BASH_REMATCH[1]} / 1000 }")
  elif [[ "$product_name" =~ ([0-9]+)L([^A-Z]|$) ]]; then
    weight=$(awk "BEGIN { printf \"%.3f\", ${BASH_REMATCH[1]} }")
  fi

  echo "--- importing: $product_name (qty: $quantity, price: $price${weight:+, weight: ${weight}kg})"

  args=("$product_name" --price "$price" --date "$created")
  [[ -n "$weight" ]]   && args+=(--amount "$weight")
  [[ -n "$store" ]]    && args+=(--store "$store")
  [[ -n "$currency" ]] && args+=(--currency "$currency")

  for ((i = 1; i <= quantity; i++)); do
    echo "" | $MYDIR/quick-product.sh "${args[@]}"
  done
done
