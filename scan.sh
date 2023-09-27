#!/bin/bash -e
# @installable
# earnings search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

input="$1"
date="$(now.sh -dt)"
pattern='*.txt'
keep=true
debug=true
confirm=true
shift

function pre_process() {
    image="$1"
    threshold=$2
    
    # apparently a max letter height of 30 pixels help. images are usually 3 times that, so we resize by 33%
    resized="$(dirname $image)/33.$(basename $image)"

    convert "$image" -resize 33% "$resized"
    img-binarize.sh "$resized" $threshold
}

function scan() {
    file="$1"

    out="$(dirname $file)/$(basename $file)"
    if [[ -f "${out}.txt" ]]; then
        info "returning cached scan: ${out}.txt"
        cat "${out}.txt"
        return 0
    fi

    processed=$(pre_process "$file")
    while [[ "$threshold" != y* ]]; do
        info "pre-processed image: ${processed}. does it look ok? input a percentage threshold to try again or 'y' to proceed"
        open.sh "$processed"
        read threshold

        if [[ $(nan.sh "$threshold") == false ]]; then
            info "processing again with threshold=$threshold ..."
            processed=$(pre_process "$file" $threshold)
        fi
    done

    tesseract "$processed" "$out" --psm 6 -c tessedit_char_whitelist="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ. (),"

    >&2 echo "$(cat $out.txt)"
    info "edit scan?"
    read confirmation

    if [[ "$confirmation" == y* ]]; then
        nano "${out}.txt" 3>&1 1>&2 2>&3
        # pid=$!
        # info "waiting $pid"
        # wait $pid
        # info "subl closed"
    fi

    info "${out}.txt - submitting..."
    cat "${out}.txt"
    [[ $keep == false ]] && rm "${out}.txt"
}

function process_scan() {
    line=$(echo "$1" | tr ',' '.' | tr -s ' ')
    [[ -z "$line" ]] && return 0

    if [[ "${line:1:1}" == " " ]]; then
        store=oxxo

        line=$(echo "$line" | cut -d' ' -f3-)
        id=$(echo "$1" | cut -d' ' -f2)

        product=$(echo "$line" | rev | cut -d' ' -f5- | rev)
        name_brand=$($query "
            select id, name, brand 
            from products 
            where market_id = '$id'
            or ocr_tags like '%${product}%'
            or similarity(name||' '||brand, '${product}') > 0.4
            order by similarity(name||' '||brand, '${product}') desc
            limit 1
        ")

        product_id=$(echo "$name_brand" | cut -d'|' -f1)
        if [[ -z "$product_id" ]]; then
            err "couldn't find a '$product' #$id"
            read confirmation </dev/tty
            return 0
        fi
        name=$(echo "$name_brand" | cut -d'|' -f2)
        brand=$(echo "$name_brand" | cut -d'|' -f3)

        multiplier=$(echo "$line" | rev | cut -d' ' -f4 | rev | cut -d'.' -f1)
        unit_price=$(echo "$line" | rev | cut -d' ' -f3 | rev)
        amount=$($query "select amount from product_ops where product_id = $product_id and trunc(price, 0) = trunc(${unit_price}, 0) order by id desc limit 1")
    else
        store=yamauchi

        line=$(echo "$line" | cut -d' ' -f2-)
        id=$(echo "$1" | cut -d' ' -f1)

        product=$(echo "$line" | rev | cut -d' ' -f4- | rev)
        product_id=''
        while [[ -z "$product_id" ]]; do
            product="${product^^}"
            name_brand=$($query "
                select id, name, brand 
                from products 
                where market_id = '$id'
                or ocr_tags like '%${id}%'
                or ocr_tags like '%${product^^}%'
                or similarity(name||' '||brand, '${product^^}') > 0.4
                order by similarity(name||' '||brand, '${product^^}') desc
                limit 1
            ")

            product_id=$(echo "$name_brand" | cut -d'|' -f1)
            if [[ -z "$product_id" ]]; then
                err "couldn't find a '$product' # $id - enter product name manually:"
                read product </dev/tty
            fi
        done

        name=$(echo "$name_brand" | cut -d'|' -f2)
        brand=$(echo "$name_brand" | cut -d'|' -f3)

        multiplier=1
        kg=$(echo "$line" | rev | cut -d' ' -f3 | rev)
        if [[ "$kg" == *KG* ]]; then
            amount=${kg//[!0-9.]/}
            unit_price=$(echo "$line" | rev | cut -d' ' -f1 | rev)
        else
            unit_price=$(echo "$line" | rev | cut -d' ' -f2 | rev)
            if [[ $(nan.sh "$unit_price") == true ]]; then
                # TODO pegar auto somehow. sugerir o último preço sei lá
                err "$id - $product - $product_id invalid unit price '${unit_price}' - enter manually..."
                read unit_price </dev/tty
            fi

            amount=$($query "select amount from product_ops where product_id = $product_id and trunc(price, 0) = trunc(${unit_price}, 0) order by id desc limit 1")
            if [[ -z "$amount" ]]; then
                err "$id - $product - no amount for $product_id ($name) [$brand] with unit price '${unit_price}' - enter manually or skip..."
                read amount </dev/tty
                [[ -z "$amount" ]] && return 0
            fi
        fi
    fi

    echo "#$product_id $store '$name' '$brand' '$amount' '$unit_price' -d '$date' -x '*$multiplier'"
    if [[ $confirm == true ]]; then
        echo "confirm?"
        read confirmation </dev/tty
        if [[ "$confirmation" == n ]]; then
            return 0
        fi
    fi

    $query "update products set market_id = '$id' where id = $product_id and market_id is null"
    dvlx-new-product "$store" "$name" "$brand" $amount $unit_price -d "$date" -x "*$multiplier"
}

function scan_dir() {
    dir="$1"
    for file in $(ls "$dir"/$pattern)
    do
        scan "$file"
    done
}

while test $# -gt 0
do
    case "$1" in
    --log)
        debug=true
    ;;
    --date|-d)
        shift
        date="$1"
    ;;
    --pattern)
        shift
        pattern="$1"
    ;;
    --out)
        shift
        out="$1"
    ;;
    --keep)
        keep=true
    ;;
    --confirm)
        confirm=true
    ;;
    -*)
        echo "$0 - bad option '$1'"
    ;;
    esac
    shift
done

if [[ -d "$input" ]]; then
    scan_dir "$input"
elif [[ -f "$input" ]]; then
    while read line
    do
        process_scan "$line"
    done < <(scan "$input")
fi