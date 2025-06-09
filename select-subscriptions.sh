#!/bin/bash -e
# @installable
# earnings search
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

$MYDIR/select-products.sh --year --subscription "$@"
