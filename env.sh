#!/bin/bash -e
VERSION=0.0.1
INSTALL_PREFIX=dvlx

if [[ $EUID -eq 0 ]]; then
    echo "this script should NOT be run as root" 1>&2
    exit 2
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
DEFAULT_CURRENCY=USD

CONFD=$HOME/.${REPO_NAME}
LOCAL_ENV=$CONFD/config

LOCAL_DB=$CONFD/db
LOGF=/tmp/$INSTALL_PREFIX.log

CACHE=/tmp/$REPO_NAME
mkdir -p $CACHE

CSCOOPER_URL='https://api.currencyscoop.com'
API_CEI_URL='https://investidor.b3.com.br/negocio-movimentacao/api'

DB_NAME=$INSTALL_PREFIX
DB_USER=postgres

# minutes before sending a repeated request. helps keeping within daily limits
API_REQUESTS_INTERVAL=60

# commom terminal colors
TCRED='\033[0;31m'
TCGREEN='\033[0;32m'
TCYELLOW='\033[0;33m'
TCBLUE='\033[0;34m'
TCPURPLE='\033[0;35m'
TCCYAN='\033[0;36m'
TCLIGHT_GRAY='\033[0;37m'
TCDARK_GRAY='\033[1;30m'
TCLIGHT_RED='\033[1;31m'
TCMAGENTA='\033[1;35m'
TCNC='\033[0m' # No Color
TCBOLD='\033[1m'

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

function cscooper_query_key() {
    echo "&api_key=$CSCOOP_KEY"
}

function cei_api_query_key() {
    echo "&cache-guid=$CEI_KEY_GUID"
}

function cei_api_auth_header() {
    if [[ "$CEI_KEY_BEARER" == "Bearer"* ]]; then
        echo "$CEI_KEY_BEARER" | cut -d' ' -f2
    else
        echo "$CEI_KEY_BEARER"
    fi
}

##
# @param $1 file to check
# @return minutes since last modification
function last_response_minutes() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		echo $API_REQUESTS_INTERVAL
		return 0
	fi

	local secs=$(echo $(($(date +%s) - $(stat -c %Y -- "$file"))))
	echo $((${secs}/60))
}

function replace_all() {
    input="$1"
    search="$2"
    replace="$3"

    echo "$input" | sed "s/$search/$replace/g"
}

function blanks() {
    input="$1"

    echo "$input" | sed "s/./ /g"
}

##
# date ops
function dop() {
    dop.sh "$1" -c "$($MYDIR/psql.sh --connection)"
}

##
# for math ops
function op() {
    expression="$1"
    round=2
    result=0.00

    while [[ $result == 0.00 ]]; do
        result=$($MYDIR/psql.sh "select round(($expression), $round)")
        round=$((round+2))
    done

    echo $result
}

function op_real() {
    expression="$1"
    $MYDIR/psql.sh "select ($expression)"
}

##
# for date ops
function interval() {
    op="$1"
    interval="$2"

    $MYDIR/psql.sh "select now() $op interval '$interval'"
}

##
# percentage difference between two values
function diff_percentage() {
    v1="$1"
    v2="$2"

    op "($v2 * 100) / $v1"
}

##
# prompt the user for an internal variable value
function prompt_conf() {
    keyname="$1"
    message="$2"
    set=false

    currval=''
    while [[ -z "$currval" ]]
	do
		err "'$keyname' not set. what's your $message?"
		read currval
        set=true
	done

	if [[ $set == true ]]; then
        prop $LOCAL_ENV $keyname "$currval"
        source $LOCAL_ENV
    fi
}

function sh_name() {
    echo "$INSTALL_PREFIX-${1/.sh/}"
}

function plot() {
    resolution=$1; shift
    value=$1; shift

    pattern='.'
    plot=O
    
    to_range1=1
    to_range2=$resolution

    while test $# -gt 0
    do
        case "$1" in
        --from-range)
            shift
            from_range1=$1

            shift
            from_range2=$1
        ;;
        --pattern)
            shift
            pattern="$1"
        ;;
        *)
            echo "$(sh_name $ME) - bad option '$1'"
            exit 1
        ;;
        esac
        shift
    done
    
    linear_transform=$(op.sh "(($value - $from_range1) / ($from_range2 - $from_range1) * ($to_range2 - $to_range1) + $to_range1)::int")
    printf %${resolution}s | tr " " "$pattern" | sed s/./$plot/$linear_transform
}

function lpad() {
    n=$1
    pads=${2:-2}
    printf "%0${pads}d\n" $n
}
