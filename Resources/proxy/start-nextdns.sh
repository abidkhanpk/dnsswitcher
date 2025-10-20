#!/usr/bin/env bash
set -euo pipefail
# Usage: start-nextdns.sh <doh_url>
DOH_URL="${1:-}"
if [[ -z "$DOH_URL" ]]; then
  echo "Usage: $0 <doh_url>" >&2
  exit 2
fi
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/nextdns-proxy"
if [[ ! -x "$BIN" ]]; then
  echo "Error: nextdns-proxy not found at $BIN" >&2
  exit 1
fi
# Listen on localhost:53 and forward all domains (.) to the specified DoH endpoint
exec "$BIN" run -listen 127.0.0.1:53 -forwarder ".=$DOH_URL" -log-queries=false -use-hosts=true -bogus-priv=true -timeout 5s -max-inflight-requests 256
