#!/usr/bin/env bash
set -euo pipefail

# Run traceroute, geo-enrich hops via ipinfo.io, and emit TSV with cache.
# Arguments: <target hostname/IP>
TARGET="$1"
CACHE_DIR="cache"
CACHE_FILE="${CACHE_DIR}/ip.tsv"

mkdir -p "$CACHE_DIR"

# Initialize cache if missing (stores basic ipinfo lookups).
if [[ ! -f "$CACHE_FILE" ]]; then
  echo -e "ip\tasn\torg\tcountry\tregion\tcity\tlat\tlon" > "$CACHE_FILE"
fi

# Print header
echo -e "ts\thop\tip\trtt_ms\tasn\torg\tcountry\tregion\tcity\tlat\tlon\tflags"

hop=0

# Single-probe traceroute to limit noise; process each hop line-by-line.
traceroute -q 1 -w 1 -m 20 -n "$TARGET" | while read -r line; do
  hop=$((hop+1))
  ts=$(date +"%Y-%m-%dT%H:%M:%S")

  ip=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\./) {print $i; exit}}')

  [[ -z "$ip" ]] && continue
  
  # Extract RTT FIRST (may be empty, but must be defined)
  rtt=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if ($(i+1)=="ms") {print $i; exit}}')

  # Short-circuit private / bogon IPs (DO NOT geo-enrich or cache via ipinfo)
  # Detect private / bogon IPs early
  if [[ "$ip" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|127\.|169\.254\.) ]]; then
    echo -e "$ip\t\t\t\t\t\t\t" >> "$CACHE_FILE"
    echo -e "$ts\t$hop\t$ip\t$rtt\t\t\t\t\t\t\tprivate_ip"
    continue
  fi

  # Recompute RTT in case earlier branch continued.
  rtt=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if ($(i+1)=="ms") {print $i; exit}}')

  flags=""

  # Private IP detection
  if [[ "$ip" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]]; then
    flags="private_ip"
  fi

  # Cache lookup for IP enrichment to avoid hammering ipinfo.
  row=$(awk -F'\t' -v ip="$ip" '$1 == ip {print; exit}' "$CACHE_FILE")


  if [[ -z "$row" ]]; then
    # Cache miss: fetch all ipinfo fields.
    asn=$(curl -s "ipinfo.io/$ip/org" | awk '{print $1}')
    org=$(curl -s "ipinfo.io/$ip/org" | sed 's/^AS[0-9]* //')
    country=$(curl -s "ipinfo.io/$ip/country")
    region=$(curl -s "ipinfo.io/$ip/region")
    city=$(curl -s "ipinfo.io/$ip/city")
    loc=$(curl -s "ipinfo.io/$ip/loc")

    lat="${loc%,*}"
    lon="${loc#*,}"

    echo -e "$ip\t$asn\t$org\t$country\t$region\t$city\t$lat\t$lon" >> "$CACHE_FILE"
  else
    IFS=$'\t' read -r _ asn org country region city lat lon <<< "$row"
  fi

  # Flag missing RTTs as likely ICMP loss.
  [[ -z "$rtt" ]] && flags="${flags:+$flags,}icmp_loss"

  echo -e "$ts\t$hop\t$ip\t$rtt\t$asn\t$org\t$country\t$region\t$city\t$lat\t$lon\t$flags"
done
