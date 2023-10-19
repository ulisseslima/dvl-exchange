#!/bin/bash -e
# https://rapidapi.com/sparior/api/yahoo-finance15
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

YFAPI_URL='https://yahoo-finance15.p.rapidapi.com/api/yahoo'

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $MYDIR/log.sh

function yfapi_header_key() {
    echo "X-RapidAPI-Key: $YFAPI_KEY"
}

function do_request() {
	method="$1"; shift
	endpoint="$1"; shift

	curl_opts="--progress-bar"
	if [[ $(debugging) == on ]]; then
		curl_opts='-v'
    fi

	debug "$curl_opts -X $method $YFAPI_URL/$endpoint"
	debug "$(yfapi_header_key)"

	request_cache="$CACHE/$1-$2.request.json"
	curl $curl_opts -X $method "$YFAPI_URL/$endpoint"\
		-H "$(yfapi_header_key)"\
		-H "X-RapidAPI-Host: yahoo-finance15.p.rapidapi.com"
}

endpoint="$1-$2"
out="$CACHE/$endpoint.response.json"
mkdir -p $(dirname "$out")
last_response=$(last_response_minutes "$out")
if [[ "$last_response" -lt $API_REQUESTS_INTERVAL ]]; then
	debug "last response to $endpoint was $last_response minutes ago. interval is $API_REQUESTS_INTERVAL minutes. returning cached response."
	info "cached response file: $out"

	# TODO return last response only if GET method. if POST, return error.
	cat "$out"
	exit 0
else
	debug "last response to $endpoint was $last_response minutes ago"
fi

response=$(do_request "$@")

echo "$response" > "$out"
debug "response cached to $out"

if [[ "$response" == *html* ]]; then
	err "$response"
fi

echo "$response"