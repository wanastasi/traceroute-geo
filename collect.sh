#!/usr/bin/env bash
# Run traceroute, geo-enrich hops via ipinfo.io, and emit TSV with cache.
# Designed to be minimally OS-specific; traceroute binary/flags are overridable.
set -euo pipefail
# Preserve tabs/newlines in reads; functions needing space splitting set IFS locally.
IFS=$'\n\t'

# Arguments: <target hostname/IP>

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <target>

Environment overrides:
  TRACEROUTE_CMD   Command to run instead of 'traceroute'
  TR_OPTS          Additional traceroute options (default: -q 1 -w 1 -m 20 -n)
EOF
}

[ $# -eq 1 ] || { usage >&2; exit 1; }

TARGET="$1"
CACHE_DIR="cache"
CACHE_FILE="${CACHE_DIR}/ip.tsv"

ensure_dirs "$CACHE_DIR" "tmp"
require_cmd curl

TR_CMD="$(choose_traceroute)"

# Build traceroute options as an array to avoid IFS issues.
if [[ -n "${TR_OPTS:-}" ]]; then
  IFS=' ' read -r -a TR_OPTS_ARR <<< "$TR_OPTS"
else
  if [[ "$TR_CMD" == "tracepath" ]]; then
    # tracepath has different flags; keep it simple and numeric output if supported.
    TR_OPTS_ARR=(-n)
  else
    TR_OPTS_ARR=(-q 1 -w 1 -m 20 -n)
  fi
fi

# Initialize cache if missing (stores basic ipinfo lookups).
if [[ ! -f "$CACHE_FILE" ]]; then
  echo -e "ip\tasn\torg\tcountry\tregion\tcity\tlat\tlon" > "$CACHE_FILE"
fi

# Print header
echo -e "ts\thop\tip\trtt_ms\tasn\torg\tcountry\tregion\tcity\tlat\tlon\tflags"

hop=0

# Run traceroute (or provided trace input) and process each hop line-by-line.
if [[ -n "${TRACE_INPUT_FILE:-}" ]]; then
  TRACE_CMD=(cat "$TRACE_INPUT_FILE")
else
  TRACE_CMD=("$TR_CMD" "${TR_OPTS_ARR[@]}" "$TARGET")
fi

"${TRACE_CMD[@]}" | while read -r line; do
  # Skip traceroute banner lines
  if [[ "$line" =~ ^traceroute\ to ]]; then
    continue
  fi

  # Hop number: prefer first token if numeric, else increment.
  first_token=$(echo "$line" | awk '{print $1}')
  if [[ "$first_token" =~ ^[0-9]+$ ]]; then
    hop=$first_token
  else
    hop=$((hop+1))
  fi

  ts=$(date +"%Y-%m-%dT%H:%M:%S")

  ip=$(echo "$line" | parse_first_ip)

  # Treat lines with no IP (e.g., "* * *") as loss rows.
  if [[ -z "$ip" ]]; then
    flags="icmp_loss"
    echo -e "$ts\t$hop\t\t\t\t\t\t\t\t\t\t$flags"
    continue
  fi

  # Extract RTT and annotations
  rtt=$(echo "$line" | parse_first_rtt)
  flag_ann=$(echo "$line" | parse_flags_from_line)
  flags="${flag_ann}"

  # Private / bogon IPs are not enriched.
  if is_private_ip "$ip"; then
    flags="${flags:+$flags,}private_ip"
    echo -e "$ts\t$hop\t$ip\t$rtt\t\t\t\t\t\t\t$flags"
    continue
  fi

  # Cache lookup for IP enrichment to avoid hammering ipinfo.
  row=$(awk -F'\t' -v ip="$ip" '$1 == ip {print; exit}' "$CACHE_FILE")

  if [[ -z "$row" ]]; then
    json=$(fetch_ipinfo_json "$ip" || true)

    # Handle lookup failures gracefully.
    if [[ -z "$json" ]] || [[ "$json" == *"Rate limit"* ]]; then
      flags="${flags:+$flags,}lookup_error"
      asn=""; org=""; country=""; region=""; city=""; lat=""; lon=""
    else
      parsed=$(parse_ipinfo_json "$json")
      IFS=$'\t' read -r asn org country region city lat lon <<< "$parsed"
      echo -e "$ip\t$asn\t$org\t$country\t$region\t$city\t$lat\t$lon" >> "$CACHE_FILE"
    fi
  else
    IFS=$'\t' read -r _ asn org country region city lat lon <<< "$row"
  fi

  # Flag missing RTTs as likely ICMP loss.
  [[ -z "$rtt" ]] && flags="${flags:+$flags,}icmp_loss"

  echo -e "$ts\t$hop\t$ip\t$rtt\t$asn\t$org\t$country\t$region\t$city\t$lat\t$lon\t$flags"
done
