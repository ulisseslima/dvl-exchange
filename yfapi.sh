#!/bin/bash -e
# https://www.yahoofinanceapi.com/
# https://www.yahoofinanceapi.com/dashboard
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $MYDIR/log.sh

function yfapi() {
	method="$1"; shift
	endpoint="$1"; shift
	body="$1"; shift
	#[[ -n "$body" ]] && body=" -d '${body//\"/\\\"}'"

	curl_opts="--progress-bar"
	if [[ $(debugging) == on ]]; then
		curl_opts='-v'
    fi

	debug "$curl_opts -X $method $YFAPI_URL/$endpoint"
	debug "$(yfapi_header_key)"
	debug "body: $body"

	request_cache="$CACHE/$1-$2.request.json"
	if [[ -f "$body" ]]; then
		cp "$body" $request_cache

		curl $curl_opts -X $method "$YFAPI_URL/$endpoint"\
			-d "@$body"\
			-H "Content-Type: application/json"\
			-H "$(yfapi_header_key)"
	elif [[ -n "$body" ]]; then
		echo "$body" > $request_cache

		curl $curl_opts -X $method "$YFAPI_URL/$endpoint"\
			-d "$body"\
			-H "Content-Type: application/json"\
			-H "$(yfapi_header_key)"
	else
		curl $curl_opts -X $method "$YFAPI_URL/$endpoint"\
			-H "$(yfapi_header_key)"
	fi
}

## TODO
# cache responses
response=$(yfapi "$@")

out="$CACHE/$1-$2.response.json"
mkdir -p $(dirname "$out")

echo "$response" > "$out"
debug "response cached to $out"

if [[ "$response" == *html* ]]; then
	err "$response"
fi

echo "$response"