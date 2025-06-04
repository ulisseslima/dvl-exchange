#!/bin/bash
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

logf="$LOGF"
if [[ -z "$logf" ]]; then
    >&2 echo "env var LOGF must be defined"
    exit 3
fi

logd="$(dirname $logf)"
if [ ! -d $logd ]; then
    mkdir -p "$logd"
fi

function debugging() {
    verbose=${1}

    confd="/tmp/log-$(basename $logf).conf.d"

    debugf="$confd/debug"
    if [ ! -f $debugf ]; then
        mkdir -p "$(dirname $debugf)"
        echo off > $debugf
        debug "all logs are saved to $LOGF"
    fi


    if [[ -n "$verbose" ]]; then
        echo $verbose > $debugf
    else
        cat $debugf
    fi
}

function log() {
    level="$1"
    shift

    TCindicator="$1"
    shift

    TCcolor="$1"
    shift

	if [[ "$1" == '-n' ]]; then
		echo ""
		shift
	fi

    if [[ $level == DEBUG && $(debugging) == on || $level != DEBUG ]]; then
        echo -e "${TCcolor}${TCindicator} $(now.sh -t) - ${FUNCNAME[2]}@${BASH_LINENO[1]}/$level:${TCNC} ${TCcolor}$@${TCNC}"
    fi
    echo -e "$MYSELF - $TCindicator $(now.sh -dt) - ${FUNCNAME[2]}@${BASH_LINENO[1]}/$level: $@" >> $logf
}

function info() {
    # change log color to $CYAN
    >&2 log INFO '###' "${TCCYAN}" "$@"
}

function err() {
    >&2 log ERROR '!!!' "${TCLIGHT_RED}" "$@"
}

function debug() {
    >&2 log DEBUG '<->' "${TCLIGHT_GRAY}" "$@"
}

function warn() {
    >&2 log WARN '???' "${TCMAGENTA}" "$@"
}

for var in "$@"
do
    case "$var" in
        --verbose|--debug|-v)
            shift
            echo "debug is on"
            debugging on
        ;;
        --quiet|-q)
            shift
            debugging off
        ;;
    esac
done
