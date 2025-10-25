#!/bin/bash -e
# https://ib.picpay.com/account/statement
# https://ib.picpay.com/api/account/statement/movements?limit=10&page=2&activities=ALL&showTodayBalance=true&filters=\[\{%22addons%22:\[\],%22id%22:%22PERIOD%22,%22values%22:\[%22LAST_90_DAYS%22\]\}\]
# https://ib.picpay.com/_next/data/XgGTK4rmVTaHBK8l3D6K_/account/statement.json?payment_type=ALL&period=LAST_90_DAYS&previousPage=%2Faccount%2Fstatement'
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $MYDIR/log.sh

URL='https://ib.picpay.com/api'
AUTH_KEY="$PICPAY_KEY" # expires in 30 min.

function do_request() {
	local method="$1"; shift
	local endpoint="$1"; shift
	local params="$1"; shift

	local curl_opts="--progress-bar -k"
	if [[ $(debugging) == on ]]; then
		local curl_opts='-kv'
    fi

	local auth="$AUTH_KEY"

	request="$URL/$endpoint?$params"
	debug "$curl_opts -X $method $request"

	request_cache="$CACHE/$method-$endpoint-$params.request.json"
	local req_debug="curl $curl_opts -X $method '$request' -H 'cookie: $auth'"
	debug "($request_cache) - $req_debug"
	echo "$req_debug" > $request_cache

	curl $curl_opts -X $method "$request" -H "cookie: $auth"
}

endpoint="$1-$2-$3"
out="$CACHE/$endpoint.response.json"
mkdir -p $(dirname "$out")
last_response=$(last_response_minutes "$out")
if [[ "$last_response" -lt $API_REQUESTS_INTERVAL && -s "$out" ]]; then
	debug "last response to $endpoint was $last_response minutes ago. interval is $API_REQUESTS_INTERVAL minutes. returning cached response."
	info "cached response file: $out"

	# TODO return last response only if GET method. if POST, return error.
	cat "$out"
	exit 0
else
	debug "last response to $endpoint was $last_response minutes ago"
fi

response=$(do_request "$@")
if [[ "$response" == *"refresh token expired"* || "$response" == *"DOCTYPE html"* ]]; then
	error=true
	err "no auth"
	response=not-authorized
elif [[ "$response" == *"Bad Request"* || "$response" == *"Internal Server Error"* ]]; then
	error=true
	err "bad request"
	cat "$request_cache"
	response=bad-request
elif [[ "$response" == *"Error 404"* ]]; then
	error=true
	err "page not found: $request"
	cat "$request_cache"
	response=page-not-found
else
	echo "$response" > "$out"
	debug "response cached to $out"
fi

if [[ "${response^^}" == *HTML* ]]; then
	err "$response"
fi

echo "$response"