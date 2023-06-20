#!/bin/bash -e
# https://www3.bcb.gov.br/sgspub/localizarseries/localizarSeries.do?method=prepararTelaLocalizarSeries
# aka bacen, banco central do brasil
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $MYDIR/log.sh

URL="https://api.bcb.gov.br/dados/serie"

function do_request() {
	local method="$1"; shift
	local endpoint="$1"; shift
	local params="$1"; shift

	local curl_opts="--progress-bar -k"
	if [[ $(debugging) == on ]]; then
		local curl_opts='-kv'
    fi

	default_params=formato=json

	request="$URL/$endpoint?${default_params}&$params"
	debug "$curl_opts -X $method $request"

	local request_cache="$CACHE/$1-$2-$3.request.json"
	info "curl $curl_opts -X $method '$request'"
	curl $curl_opts -X $method "$request"
}

endpoint="$1-$2-$3"
out="$CACHE/$endpoint.response.json"
mkdir -p $(dirname "$out")
last_response=$(last_response_minutes "$out")
if [[ -s "$out" ]]; then
	debug "last response to $endpoint was $last_response minutes ago. interval is $API_REQUESTS_INTERVAL minutes. returning cached response."
	info "cached response file: $out"

	# TODO return last response only if GET method. if POST, return error.
	cat "$out"
	exit 0
else
	debug "last response to $endpoint was $last_response minutes ago"
fi

response=$(do_request "$@")
if [[ "$response" == *"Authorization Required"* || "$response" == *"Sem autorizacao para consumir a API"* ]]; then
    err "not caching error response"
	>&2 echo "$response"
	response=not-authorized
elif [[ "${response^^}" == *HTML* ]]; then
	err "$response"
	response=fail
else
	echo "$response" > "$out"
	debug "response cached to $out"
fi

echo "$response"
