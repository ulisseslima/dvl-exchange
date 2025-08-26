#!/bin/bash -e
# @installable
# br CDI index
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

# TODO get today's/this month's/this year's value automatically
annual_percentage=13.0
percent_variation=102.0

while test $# -gt 0
do
    case "$1" in
    --value)
      shift
      annual_percentage=$1
    ;;
    --ref)
      shift
      percent_variation="$1"
    ;;
    *)
      echo "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

op "${annual_percentage}*(${percent_variation}/100)"