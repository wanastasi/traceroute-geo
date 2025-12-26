#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR%/tests}"
cd "$ROOT_DIR"

fail() { echo "[FAIL] $1" >&2; exit 1; }
pass() { echo "[PASS] $1"; }

fixture="tests/fixtures/sample.tsv"
[ -f "$fixture" ] || fail "fixture missing: $fixture"

summary_out=$(./summary.sh "$fixture")
asn_out=$(./asn-summary.sh "$fixture")

# Summary expectations (order-sensitive for key lines; countries checked by membership)
grep -F "Total hops: 4" <<< "$summary_out" || fail "summary total hops"
grep -F "RTT min / avg / max: 1 / " <<< "$summary_out" || fail "summary rtt line"
grep -F "Largest RTT jump: 20 ms at hop 4" <<< "$summary_out" || fail "summary largest jump"
grep -F "ASN handoffs: 2" <<< "$summary_out" || fail "summary handoffs"
grep -F "Unique ASNs: 3" <<< "$summary_out" || fail "summary unique ASNs"
grep -F "ICMP loss: 1 hops (25%)" <<< "$summary_out" || fail "summary loss"
grep -F "  - US" <<< "$summary_out" || fail "summary country US"
grep -F "  - CA" <<< "$summary_out" || fail "summary country CA"
pass "summary checks"

# ASN summary expectations (exact lines)
grep -F $'AS13335\tCloudflare, Inc.\tSan Francisco\tUS\tSan Francisco\tUS\t10.0\t10.0\t0.0' <<< "$asn_out" || fail "asn summary AS13335"
grep -F $'AS64512\tExampleNet\tDallas\tUS\tDallas\tUS\t0.0\t0.0\t0.0' <<< "$asn_out" || fail "asn summary AS64512"
grep -F $'AS65500\tOtherNet\tOttawa\tCA\tOttawa\tCA\t30.0\t30.0\t0.0' <<< "$asn_out" || fail "asn summary AS65500"
pass "asn-summary checks"

echo "All tests passed."
