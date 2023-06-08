#!/bin/bash -e
# https://currencyscoop.com/account
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $MYDIR/log.sh

URL=$CSCOOPER_URL
function do_request() {
	method="$1"; shift
	endpoint="$1"; shift
	body="$1"; shift
	#[[ -n "$body" ]] && body=" -d '${body//\"/\\\"}'"

	curl_opts="--location --progress-bar"
	if [[ $(debugging) == on ]]; then
		curl_opts='-v'
    fi

	debug "curl $curl_opts -X $method '$URL/${endpoint}$(cscooper_query_key)'"
	debug "body: $body"

	request_cache="$CACHE/$1-$2.request.json"
	if [[ -f "$body" ]]; then
		cp "$body" $request_cache

		curl $curl_opts -X $method "$URL/$endpoint"\
			-d "@$body"\
			-H "Content-Type: application/json"
	elif [[ -n "$body" ]]; then
		echo "$body" > $request_cache

		curl $curl_opts -X $method "$URL/$endpoint"\
			-d "$body"\
			-H "Content-Type: application/json"
	else
		curl $curl_opts -X $method "$URL/${endpoint}$(cscooper_query_key)"
	fi
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

if [[ "$response" == *html* ]]; then
	err "$response"
else
	echo "$response" > "$out"
	debug "response cached to $out"
	echo "$response"
fi
