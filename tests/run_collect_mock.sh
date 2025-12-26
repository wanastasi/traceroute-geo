#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR%/tests}"
cd "$ROOT_DIR"

fail() { echo "[FAIL] $1" >&2; exit 1; }
pass() { echo "[PASS] $1"; }

fixture_tr="tests/fixtures/traceroute_mock.txt"
[ -f "$fixture_tr" ] || fail "fixture missing: $fixture_tr"

# Simulate traceroute by feeding fixture; avoid network and actual traceroute.
output=$(TRACE_INPUT_FILE="$fixture_tr" ./collect.sh example.com)

# Basic assertions on parsed lines
grep -F $'1\t192.168.0.1' <<< "$output" || fail "parsed hop 1"
grep -F $'2\t10.0.0.1' <<< "$output" || fail "parsed hop 2"
grep -F $'3\t1.1.1.1' <<< "$output" || fail "parsed hop 3"
grep -F "!N" <<< "$output" || fail "flag !N captured"
grep -F "icmp_loss" <<< "$output" || fail "loss captured"
pass "collect mock parse"

echo "All collect mock tests passed."
