#!/bin/bash -e
# 2d series plotter for cli charts
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

psql=$MYDIR/psql.sh

query="$1"
require query
debug "original query: $query"

chart_resolution=10

while test $# -gt 0
do
    case "$1" in
    --col*|-c)
        shift
        column="$1"
    ;;
    --resolution)
        shift
        chart_resolution=$1
    ;;
    -*)
        echo "$(sh_name $ME) - bad option '$1'"
    ;;
    esac
    shift
done

# query=$(echo "$query" | sed -E "s/plot\((.*)\)/'\1'/")
while read column
do
    require column 'specify plot:column_name'

    # real_column=$(echo $query | grep -oP "(?<=,).*(?=\sas\s${column})" | sed 's/^[ \t]*//')
    # real_column=$(echo "$query" | grep " as ${column}" | tr -s " " | cut -d'.' -f1,2)
    real_column=$(echo "$query" | grep " as ${column}" | tr -s " ")
    real_column=$(echo $real_column)
    # real_column=$(echo $real_column | cut -d' ' -f1)
    real_column=$(echo $real_column | rev | cut -d' ' -f3- | rev | tr '/' '\/')

    require real_column "couldn't find column from '$column' alias"

    min_max=$($psql "select min($column), max($column) from ($query) as q")
    debug "range: $min_max - real col: '$real_column'"
    min=$(echo "$min_max" | cut -d'|' -f1)
    max=$(echo "$min_max" | cut -d'|' -f2)

    if [[ "$real_column" == *'/'* && "$real_column" == *'|'* ]]; then
        err "unparseable column, contains / and |: $real_column"
        exit 1
    fi
    
    if [[ "$real_column" == *'/'* ]]; then
        query=$(echo "$query" | sed -E "s|'plot:${column}'|plot\($real_column, $chart_resolution, $min, $max\) as plot_${column}|")
    else
        query=$(echo "$query" | sed -E "s/'plot:${column}'/plot\($real_column, $chart_resolution, $min, $max\) as plot_${column}/")
    fi
    debug "${column}: updated query: $query"
done < <(echo "$query" | grep 'plot:' | cut -d':' -f2 | tr -d "'" | tr -d ",")

echo "$query"