#!/usr/bin/env bash
set -euo pipefail

# Orchestrate collection + summary for a target and store artifacts.
# Arguments: <target hostname/IP>
TARGET="$1"
TS="$(date +%Y%m%d-%H%M%S)"
TMP_FILE="tmp/trgeo-${TARGET//[^a-zA-Z0-9]/_}-${TS}.tsv"

echo "Tracing $TARGET..."
echo

# Live output + save artifact
./collect.sh "$TARGET" | tee "$TMP_FILE"

echo
echo "----- SUMMARY -----"
./summary.sh "$TMP_FILE"

echo
echo "Raw trace saved to: $TMP_FILE"

echo
echo "----- ASN SUMMARY -----"
./asn-summary.sh "$TMP_FILE" 