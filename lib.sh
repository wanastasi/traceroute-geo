#!/usr/bin/env bash
# Shared helpers for traceroute enrichment scripts.
# Keep POSIX-ish where possible; Bash used for arrays and stricter options.
set -euo pipefail
# Avoid splitting on spaces to keep TSV fields intact; functions that need
# space splitting use their own IFS.
IFS=$'\n\t'

# Fail with a message.
die() {
  echo "${1}" >&2
  exit 1
}

# Ensure required binary exists.
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

# Create directories if they do not exist.
ensure_dirs() {
  for d in "$@"; do
    [ -d "$d" ] || mkdir -p "$d"
  done
}

# Decide which traceroute binary to call. Caller may override with TRACEROUTE_CMD.
choose_traceroute() {
  # Respect explicit override.
  if [ -n "${TRACEROUTE_CMD:-}" ]; then
    echo "$TRACEROUTE_CMD"
    return 0
  fi

  # Prefer traceroute when available.
  if command -v traceroute >/dev/null 2>&1; then
    echo "traceroute"
    return 0
  fi

  # Fallback to tracepath if present (Linux); caller must adjust options.
  if command -v tracepath >/dev/null 2>&1; then
    echo "tracepath"
    return 0
  fi

  die "traceroute/tracepath not found (set TRACEROUTE_CMD to override)"
}

# Detect RFC1918 IPv4, loopback, link-local, and basic IPv6 local scopes.
is_private_ip() {
  local ip="$1"
  if [[ "$ip" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|127\.|169\.254\.) ]]; then
    return 0
  fi
  if [[ "$ip" =~ ^fe80: ]] || [[ "$ip" =~ ^fc00: ]] || [[ "$ip" =~ ^fd00: ]]; then
    return 0
  fi
  return 1
}

# Finds first IPv4 or IPv6 token in a line.
parse_first_ip() {
  awk '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ || $i ~ /:/) { print $i; exit }
    }
  }'
}

# Extract first RTT value preceding an ms token.
parse_first_rtt() {
  awk '{
    for (i = 1; i <= NF; i++) {
      if ($(i+1) ~ /^ms/) { print $i; exit }
    }
  }'
}

# Extract traceroute annotations like !H, !N, !X into comma-separated flags.
parse_flags_from_line() {
  awk '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^!/) { printf("%s%s", (out==""?"":","), $i); out=1 }
    }
  }'
}

# Fetch ipinfo JSON with a small timeout. Caller handles empty/failed responses.
fetch_ipinfo_json() {
  local ip="$1"
  curl -s --max-time 5 "https://ipinfo.io/${ip}/json"
}

# Parse ipinfo JSON into TSV fields: asn org country region city lat lon.
parse_ipinfo_json() {
  local json="$1"

  if command -v jq >/dev/null 2>&1; then
    local asn org country region city loc lat lon
    asn=$(echo "$json" | jq -r '(.org // "") | split(" ")[0] // ""')
    org=$(echo "$json" | jq -r '(.org // "") | split(" ")[1:] | join(" ")')
    country=$(echo "$json" | jq -r '.country // ""')
    region=$(echo "$json" | jq -r '.region // ""')
    city=$(echo "$json" | jq -r '.city // ""')
    loc=$(echo "$json" | jq -r '.loc // ""')
    lat="${loc%,*}"
    lon="${loc#*,}"
    echo -e "${asn}\t${org}\t${country}\t${region}\t${city}\t${lat}\t${lon}"
  else
    # Minimal parsing without jq; best-effort string slicing.
    local asn org country region city loc lat lon
    asn=$(echo "$json" | sed -n 's/.*"org" *: *"AS\([0-9]*\)[^"]*".*/AS\1/p' | head -n1)
    org=$(echo "$json" | sed -n 's/.*"org" *: *"AS[0-9]* \([^"]*\)".*/\1/p' | head -n1)
    country=$(echo "$json" | sed -n 's/.*"country" *: *"\([^"]*\)".*/\1/p' | head -n1)
    region=$(echo "$json" | sed -n 's/.*"region" *: *"\([^"]*\)".*/\1/p' | head -n1)
    city=$(echo "$json" | sed -n 's/.*"city" *: *"\([^"]*\)".*/\1/p' | head -n1)
    loc=$(echo "$json" | sed -n 's/.*"loc" *: *"\([^"]*\)".*/\1/p' | head -n1)
    lat="${loc%,*}"
    lon="${loc#*,}"
    echo -e "${asn}\t${org}\t${country}\t${region}\t${city}\t${lat}\t${lon}"
  fi
}
