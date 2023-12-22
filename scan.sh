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

psql=$MYDIR/psql.sh

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

    # psm 6, best for simple line by line text
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

    multiplier=1

    if [[ "$store" == oxxo ]]; then
        info "store=$store"

        line=$(echo "$line" | cut -d' ' -f2-)
        id=$(echo "$1" | cut -d' ' -f1)

        product=$(echo "$line" | rev | cut -d' ' -f5- | rev)
	    similar_query="
            select id, name, brand
            from products
            where market_id = '$id'
            or ocr_tags like '%${product}%'
            or similarity(name||' '||brand, '${product}') > 0.15
            order by similarity(name||' '||brand, '${product}') desc
            limit 1
        "
	    debug "$similar_query"
        name_brand=$($psql "$similar_query")

        product_id=$(echo "$name_brand" | cut -d'|' -f1)
        if [[ -z "$product_id" ]]; then
            err "couldn't find a '$product' #$id. enter manually in the format name|brand"
            read name_brand </dev/tty
            name_brand="0|${name_brand}"
            info "name_brand=$name_brand"
        else
            amount=$($psql "select amount from product_ops where product_id = $product_id order by id desc limit 1")
        fi
        name=$(echo "$name_brand" | cut -d'|' -f2)
        brand=$(echo "$name_brand" | cut -d'|' -f3)

        multiplier=$(echo "$line" | rev | cut -d' ' -f4 | rev | cut -d'.' -f1)
        if [[ $(nan.sh $multiplier) == true ]]; then
            multiplier=1
        fi
        
        unit_price=$(echo "$line" | rev | cut -d' ' -f3 | rev | tr -d '()')
        if [[ $(nan.sh $unit_price) == true ]]; then
            err "fix unit price: $unit_price"
            read unit_price
        fi

        if [[ -n "$product_id" ]]; then
                amount=$($psql "select amount from product_ops where product_id = $product_id and trunc(price, 0) = trunc(${unit_price}, 0) order by id desc limit 1" || true)
        fi

        if [[ -z "$amount" ]]; then
            err "$id - $product - no amount for #$product_id ($name) [$brand] with unit price '${unit_price}' - enter manually or press enter to skip product..."
            read amount </dev/tty
            [[ -z "$amount" ]] && return 0
        fi
    elif [[ "$store" == 'assaí' ]]; then
        store=assaí
        info "store=$store [$buffer]"

        if [[ "$buffer" != true ]]; then
            buffer=true
            amount=''

            line1=$(echo "$line" | cut -d' ' -f2-)
            info "line1: '$line1'"

            id=$(echo "$line1" | cut -d' ' -f1)

            product=$(echo "$line1" | cut -d' ' -f2-)
            info "searching for '$product' and similar..."
            name_brand=$($psql "
                select id, name, brand
                from products
                where market_id = '$id'
                or ocr_tags like '%${product}%'
                or similarity(name||' '||brand, '${product}') > 0.15
                order by similarity(name||' '||brand, '${product}') desc
                limit 1
            ")

            product_id=$(echo "$name_brand" | cut -d'|' -f1)
            if [[ -z "$product_id" ]]; then
                err "couldn't find a '$product' #$id. enter manually in the format name|brand"
                read name_brand </dev/tty
                name_brand="0|${name_brand}"
                info "name_brand=$name_brand"
            else
                amount=$($psql "select amount from product_ops where product_id = $product_id order by id desc limit 1")
            fi
            name=$(echo "$name_brand" | cut -d'|' -f2)
            brand=$(echo "$name_brand" | cut -d'|' -f3)
        else
            buffer=false

            line2="$line"
            info "line2: '$line2'"

            unit_price=$(echo "$line2" | rev | cut -d' ' -f1 | rev)

            amount2=$(echo "$line2" | cut -d' ' -f1)
            if [[ -n "$amount2" && "$amount2" != '1.0'* ]]; then
                if [[ $(nan.sh $amount2) == false && "$amount2" == *'.000' ]]; then
                    multiplier=$(echo "$amount2" | cut -d'.' -f1)
                    is_multiplier=true
                fi
            fi

            if [[ -n "$amount2" && "$amount2" != '1.0'* && "$is_multiplier" != true ]]; then
                amount=$(echo "$amount2" | tr 'O' '0')
            elif [[ -n "$product_id" ]]; then
                amount2=$($psql "select amount from product_ops where product_id = $product_id and trunc(price, 0) = trunc(${unit_price}, 0) order by id desc limit 1")
                if [[ -n "$amount2" ]]; then
                    amount="$amount2"
                fi
            fi

            if [[ -z "$amount" ]]; then
                amount="$amount2"
            fi
        fi
    elif [[ "$store" == 'yamauchi' ]]; then
        info "store=$store"

        line=$(echo "$line" | cut -d' ' -f2-)
        id=$(echo "$1" | cut -d' ' -f1)

        product=$(echo "$line" | rev | cut -d' ' -f4- | rev)
        product_id=''
        while [[ -z "$product_id" ]]; do
            product="${product^^}"
            name_brand=$($psql "
                select id, name, brand
                from products
                where market_id = '$id'
                or ocr_tags like '%${id}%'
                or ocr_tags like '%${product^^}%'
                or similarity(name||' '||brand, '${product^^}') > 0.15
                order by similarity(name||' '||brand, '${product^^}') desc
                limit 1
            ")

            product_id=$(echo "$name_brand" | cut -d'|' -f1)
            if [[ -z "$product_id" ]]; then
                err "couldn't find a '$product' #$id. enter manually in the format name|brand"
                read name_brand </dev/tty
                name_brand="0|${name_brand}"
                info "name_brand=$name_brand"
                break
            else
                amount=$($psql "select amount from product_ops where product_id = $product_id order by id desc limit 1")
            fi
        done

        name=$(echo "$name_brand" | cut -d'|' -f2)
        brand=$(echo "$name_brand" | cut -d'|' -f3)

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

            if [[ -z "$product_id" && -z "$unit_price" ]]; then
                amount=$($psql "select amount from product_ops where product_id = $product_id and trunc(price, 0) = trunc(${unit_price}, 0) order by id desc limit 1")
            fi

            if [[ -z "$amount" ]]; then
                err "$id - $product - no amount for #$product_id ($name) [$brand] with unit price '${unit_price}' - enter manually or skip..."
                read amount </dev/tty
                [[ -z "$amount" ]] && return 0
            fi
        fi
    fi

    if [[ "$buffer" == true ]]; then
        info "[$buffer] continuing on next line..."
        return 0
    fi

    if [[ -z "$amount" || "$amount" == 0.00 ]]; then
        info "defauting amount to 1..."
        amount=1
    fi

    echo "#$product_id $store '$name' '$brand' '$amount' '$unit_price' -d '$date' -x '*$multiplier'"
    echo "$name|$brand|$amount|$unit_price" | ctrlc.sh
    if [[ $confirm == true ]]; then
        echo "confirm? (fix values using the format name|brand|amount|unit_price [curr values on clipboard]) reject with 'n'"
        read confirmation </dev/tty
        if [[ "$confirmation" == n ]]; then
            return 0
        elif [[ -n "$confirmation" ]]; then
            name=$(echo "$confirmation" | cut -d'|' -f1)
            brand=$(echo "$confirmation" | cut -d'|' -f2)
            amount=$(echo "$confirmation" | cut -d'|' -f3)
            unit_price=$(echo "$confirmation" | cut -d'|' -f4)
        fi
    fi

    if [[ -n "$product_id" ]]; then
        $psql "update products set market_id = '$id' where id = $product_id and market_id is null"
    fi
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
    --store|-s)
        shift
        store="$1"
    ;;
    --keep)
        keep=true
    ;;
    --oxxo)
        store=oxxo
    ;;
    --assai)
        store=assaí
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

require store

if [[ -d "$input" ]]; then
    scan_dir "$input"
elif [[ -f "$input" ]]; then
    while read line
    do
        process_scan "$line"
    done < <(scan "$input")
fi
