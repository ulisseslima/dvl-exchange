#!/bin/bash -e
# https://currencyscoop.com/account
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $MYDIR/log.sh

# minutes before sending a repeated request. helps keeping within daily limits
REQUESTS_INTERVAL=60
URL=$CSCOOPER_URL

##
# @param $1 file to check
# @return minutes since last modification
function last_response_minutes() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		echo $REQUESTS_INTERVAL
		return 0
	fi

	local secs=$(echo $(($(date +%s) - $(stat -c %Y -- "$file"))))
	echo $((${secs}/60))
}

function do_request() {
	method="$1"; shift
	endpoint="$1"; shift
	body="$1"; shift
	#[[ -n "$body" ]] && body=" -d '${body//\"/\\\"}'"

	curl_opts="--progress-bar"
	if [[ $(debugging) == on ]]; then
		curl_opts='-v'
    fi

	debug "$curl_opts -X $method $URL/$endpoint"
	debug "$(cscooper_query_key)"
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
		curl $curl_opts -X $method "$URL/$endpoint?$(cscooper_query_key)"
	fi
}

endpoint="$1-$2"
out="$CACHE/$endpoint.response.json"
mkdir -p $(dirname "$out")
last_response=$(last_response_minutes "$out")
if [[ "$last_response" -lt $REQUESTS_INTERVAL ]]; then
	info "last response to $endpoint was $last_response minutes ago. interval is $REQUESTS_INTERVAL minutes. returning cached response."
	debug "cached response file: $out"

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