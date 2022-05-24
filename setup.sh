#!/bin/bash -e
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $MYDIR/log.sh
[[ "$SETUP_DEBUG" == true ]] && debugging on
source $MYDIR/db.sh

##
# called on error
function failure() {
  local lineno=$1
  local msg=$2
  echo "Failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

##
# assert a web address is up
function assert_is_up() {
    address="$1"
    debug "checking if $address is up..."
    curl -sSf "$address" > /dev/null
}

##
# prompt the user for an internal variable value
function prompt() {
    keyname="$1"
    message="$2"
    currval="${!keyname}"
    set=false

    while [[ ! -n "$currval" ]]
	do
		err "'$keyname' not set. what's your $message?"
		read currval
        set=true
	done

	if [[ $set == true ]]; then
        prop $LOCAL_ENV $keyname $currval
        source $LOCAL_ENV
    fi
}

##
# put stuff on PATH
function install() {
    debug "updating installation..."
    uninstall

    while read script
    do
        name=$(basename $script)

        iname="$INSTALL_PREFIX-${name/.sh/}"
        iname="${iname/-rr-/-}"
        fname="/usr/local/bin/$iname"

        sudo ln -s $script $fname
        info "installed $fname ..."
    done < <(grep -l '@installable' $CLIT/* | grep -v setup)

    debug "installation finished."
}

##
# remove stuff from PATH
function uninstall() {
    # unsafe
    sudo rm -f /usr/local/bin/${INSTALL_PREFIX}-*
}

function local_db() {
    info "checking if dpkg is available..."
    [[ ! -n "$(which dpkg)" ]] && return 0
    
    info "checking if postgresql client is available..."
    [[ "$(dpkg -l | grep -c postgresql-client)" -lt 1 ]] && return 0

    info "checking if postgresql server is available..."
    [[ "$(dpkg -l | grep postgresql | grep -c server)" -lt 1 ]] && return 0

    info "checking if db already created..."
    if [[ -n "$($MYDIR/psql.sh 'select id from tickers limit 1')" ]]; then
        info "database already created."
    else
        # TODO check permissions, maybe echo commands to give necessary privileges
        info "we detected you have a postgresql server. installing database..."

        info "creating database..."
        $MYDIR/psql.sh --create-db
        $MYDIR/psql.sh $MYDIR/db/db.sql

        db DB_ENABLED yes
        info "database enabled"
    fi

    if [[ ! -d "$MYDIR/node_modules" ]]; then
        cd $MYDIR
        npm init -y
        npm i dotenv pg
    fi

    node_env=$MYDIR/.env
    if [[ ! -f "$node_env" ]]; then
        echo "DATABASE_URL=postgres://localhost:5432/$DB_NAME" > $node_env
        echo "DB_NAME=$DB_NAME" >> $node_env
        echo "DB_USER=$DB_USER" >> $node_env
        echo "DB_PASS=$DB_PASS" >> $node_env
    fi
}

##
# check pre requisites
function check_requirements() {
    check_installed python --version
    check_installed xmlstarlet --version
}

##
# build initial config.
function wizard() {
	debug "checking configuration..."

    check_requirements
    install

    prompt PGPASSWORD "postgres password for $USER"
    prompt YFAPI_KEY "Yahoo Finance API Key"
    prompt CSCOOP_KEY "Currency Scooper API Key"
    #prompt CEI_KEY_GUID "CEI cache-guid"
    #prompt CEI_KEY_BEARER "CEI Auth Bearer"

    local_db

	debug "local settings saved to $LOCAL_ENV"
}

wizard