#!/bin/bash -e
# https://www.investidor.b3.com.br/
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $MYDIR/log.sh

URL=$API_CEI_URL
function do_request() {
	local method="$1"; shift
	local endpoint="$1"; shift
	local params="$1"; shift

	local curl_opts="--progress-bar -k"
	if [[ $(debugging) == on ]]; then
		local curl_opts='-kv'
    fi

	# local query_key="$(cei_api_query_key)"
	local auth_header="$(cei_api_auth_header)"

	# request="$URL/$endpoint?$query_key&$params"
	request="$URL/$endpoint?$params"
	debug "$curl_opts -X $method $request"

	local request_cache="$CACHE/$1-$2-$3.request.json"
	debug "curl $curl_opts -X $method '$request' -H 'Authorization: Bearer $auth_header'"
	curl $curl_opts -X $method "$request"\
		-H "Authorization: Bearer $auth_header"
}

endpoint="$1-$2-$3"
out="$CACHE/$endpoint.response.json"
mkdir -p $(dirname "$out")
last_response=$(last_response_minutes "$out")
if [[ "$last_response" -lt $API_REQUESTS_INTERVAL && -s "$out" ]]; then
	debug "last response to $endpoint was $last_response minutes ago. interval is $API_REQUESTS_INTERVAL minutes. returning cached response."
	debug "cached response file: $out"

	# TODO return last response only if GET method. if POST, return error.
	cat "$out"
	exit 0
else
	debug "last response to $endpoint was $last_response minutes ago"
fi

response=$(do_request "$@")
if [[ "$response" == *"Authorization Required"* || "$response" == *"Sem autorizacao para consumir a API"* ]]; then
    info "not caching error response"
	>&2 echo "$response"
	response=not-authorized
else
	echo "$response" > "$out"
	debug "response cached to $out"
fi

if [[ "${response^^}" == *HTML* ]]; then
	err "$response"
fi

echo "$response"