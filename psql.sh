#!/bin/bash -e
# @installable
# queries the local database
X=$(dirname `readlink -f ${BASH_SOURCE[0]}`)
source $X/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $X/log.sh

MYSELF() { readlink -f "${BASH_SOURCE[0]}"; }
MYDIR() { echo "$(dirname $(MYSELF))"; }
MYNAME() { echo "$(basename $(MYSELF))"; }
CALLER=$(basename `readlink -f $0`)

# TODO support for different ports and hosts
connection="psql -U $DB_USER $DB_NAME"
ops='qAtX'
separator="|"

if [[ $# -lt 1 ]]; then
    $connection
fi

query="$1"; shift
if [[ ! -n "$query" ]]; then
    err "arg 1 must be the query"
    exit 6
fi

if [[ "$query" == --create-db ]]; then
    info "starting db $DB_NAME ..."
    psql -U $DB_USER -c "create database $DB_NAME"
    exit 0
fi

if [[ "$query" == --connection ]]; then
    echo "$connection"
    exit 0
fi

while test $# -gt 0
do
    case "$1" in
    --separator|-s)
        shift
        separator="$1"
    ;;
    --ops)
        shift
        ops="$1"
    ;;
    --full)
        ops="c"
    ;;
    --csv)
        noop="TODO"
    ;;
    -f)
        shift
        field="$1"
    ;;
    -*)
        echo "$0 - bad option '$1'"
        exit 6
    ;;
    esac
    shift
done

if [[ -f "$query" ]]; then
    result=$($connection -$ops --field-separator="$separator" < "$query")
else
    result=$($connection -$ops --field-separator="$separator" -c "$query")
fi

if [[ -z "$field" ]]; then
    echo "$result"
else
    echo "$result" | cut -d"$separator" -f$field
fi