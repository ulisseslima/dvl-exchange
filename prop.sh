#!/bin/bash
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $MYDIR/log.sh

function prop() {
  filename="$1"
  thekey="$2"
  newvalue="$3"
  
  if [[ -z "$newvalue" ]]; then
    debug "GETTING '${thekey}'"
    sed -rn "s/^${thekey}=([^\n]+)$/\1/p" $filename
    exit 555
  fi

  if [ ! -f "$filename" ]; then
    debug "creating config file $filename"
    mkdir -p "$(dirname $filename)"
    touch "$filename"
  fi

  if ! grep -R "^[#]*\s*${thekey}=.*" $filename > /dev/null; then
    # include key if not exists
    debug "APPENDING '${thekey}'"
    echo "$thekey=$newvalue" >> $filename
  else
    debug "SETTING '${thekey}'"
    if [[ "$newvalue" == */* ]]; then
      newvalue="${newvalue//\//\\\/}"
      debug "value escaped as: $newvalue"
    fi

    sed -ir "s/^[#]*\s*${thekey}=.*/$thekey=$newvalue/" $filename
  fi
}

function clear_prop() {
  filename="$1"
  thekey="$2"

  info "CLEARING '${thekey}'"
  if ! grep -R "^[#]*\s*${thekey}=.*" $filename > /dev/null; then
    info "APPENDING '${thekey}'"
    echo "${thekey}=" >> $filename
  else
    info "UPDATING '${thekey}'"
    sed -ir "s/^[#]*\s*${thekey}=.*/$thekey=/" $filename
  fi
}