#!/bin/bash -e
VERSION=0.0.1
INSTALL_PREFIX=dvlx

if [[ $EUID -eq 0 ]]; then
    echo "this script should NOT be run as root" 1>&2
    exit 1
fi

# these settings can be overridden by creating $LOCAL_ENV
SETUP_DEBUG=true

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
CLIT="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
REPO_DIR=$CLIT
REPO_NAME=$(basename $REPO_DIR)

TODAY=$(now.sh -d)
CONFD=$HOME/.${REPO_NAME}
LOCAL_ENV=$CONFD/config

LOCAL_DB=$CONFD/db
LOGF=/tmp/$INSTALL_PREFIX.log

CACHE=/tmp/$REPO_NAME
mkdir -p $CACHE

YFAPI_URL='https://yfapi.net'

DB_NAME=$INSTALL_PREFIX
DB_USER=$USER

function nan() {
    in="$1"

    regex='^[0-9.]+$'
    if ! [[ "$in" =~ $regex ]] ; then
        echo true
    else
        echo false
    fi
}

function safe_name() {
    # remove non ascii:
    name=$(echo "$1" | iconv -f utf8 -t ascii//TRANSLIT)
    # to lower case:
    name=$(echo ${name,,})
    # replace spaces for "-", then remove anything that's non alphanumeric
    echo ${name// /-} | sed 's/[^a-z0-9-]//g'
}

function check_installed() {
	echo ""
	echo "checking if $1 is installed..."
	$@
}

function yfapi_header_key() {
    echo "X-API-KEY: $YFAPI_KEY"
}
