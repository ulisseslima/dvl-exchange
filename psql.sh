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

##
# called on error
function failure() {
  local lineno=$1
  local msg=$2
  echo "$(basename $0): Failed at $lineno: '$msg' - query:"
  echo "$query"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

# TODO support for different ports and hosts
connection="psql -h localhost -U $DB_USER $DB_NAME"
debug "connection=$connection"

ops='qAtX'
separator="|"

if [[ $# -lt 1 ]]; then
    echo "$connection"
    $connection
fi

query="$1"; shift
if [[ ! -n "$query" ]]; then
    err "qerr - arg1 must be the query"
    exit 6
fi

if [[ "$query" == --create-db ]]; then
    info "starting db $DB_NAME ..."
    psql -U $DB_USER -h localhost postgres -c "create database $DB_NAME"
    exit 0
fi

if [[ "$query" == --connection ]]; then
    echo "$connection"
    exit 0
elif [[ "$query" == --url ]]; then
    echo "postgresql://$DB_USER@localhost/$DB_NAME"
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
        echo "$(sh_name $ME) - bad option '$1'"
        exit 6
    ;;
    esac
    shift
done

if [[ -f "$query" ]]; then
    debug "$(cat "$query")"
    result=$($connection -$ops --field-separator="$separator" < "$query")
else
    debug "$query"
    result=$($connection -$ops --field-separator="$separator" -c "$query")
fi

if [[ -z "$field" ]]; then
    echo -e "$result"
else
    echo "$result" | cut -d"$separator" -f$field
fi
