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

debug "plot original: $query"
# query=$(echo "$query" | sed -E "s/plot\((.*)\)/'\1'/")
column=$(echo "$query" | grep 'plot:' | cut -d':' -f2 | tr -d "'")
# real_column=$(echo $query | grep -oP "(?<=,).*(?=\sas\s${column})" | sed 's/^[ \t]*//')
real_column=$(echo "$query" | grep " as ${column}," | tr -s " " | cut -d'.' -f1,2)
real_column=$(echo $real_column)
real_column=$(echo $real_column | cut -d' ' -f1)

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

require column 'specify --column name or plot:column_name'

min_max=$($psql "select min($column), max($column) from ($query) as q")
debug "range: $min_max - real col: '$real_column'"
min=$(echo "$min_max" | cut -d'|' -f1)
max=$(echo "$min_max" | cut -d'|' -f2)

debug "new q: $(echo "$query" | sed -E "s/'plot:(.*)'/plot\($real_column, $chart_resolution, $min, $max\)/")"
echo "$query" | sed -E "s/'plot:(.*)'/plot\($real_column, $chart_resolution, $min, $max\)/"