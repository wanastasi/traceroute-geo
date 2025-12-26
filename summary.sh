#!/usr/bin/env bash
set -euo pipefail

# Compute high-level route statistics from traceroute TSV.
# Input columns: hop (#2), RTT (#4), ASN (#5), country (#7).
FILE="$1"

awk -F'\t' '
NR>1 {
  hops++
  if ($4 != "") {
    rtt_sum += $4
    rtt_count++
    if (min=="" || $4 < min) min=$4
    if (max=="" || $4 > max) max=$4
    if (prev_rtt != "") {
      delta = $4 - prev_rtt
      if (delta > max_delta) {
        max_delta = delta
        delta_hop = $2
      }
    }
    prev_rtt = $4
  } else {
    loss++
  }

  if ($5 != "") asn[$5]++
  if ($7 != "") country[$7]++

  if (prev_asn != "" && $5 != "" && $5 != prev_asn) {
    handoffs++
  }
  prev_asn = $5
}
END {
  print "Route Summary"
  print "-------------"
  print "Total hops:", hops
  print "RTT min / avg / max:", min " / " (rtt_sum/rtt_count) " / " max " ms"
  print "Largest RTT jump:", max_delta " ms at hop", delta_hop
  print "ASN handoffs:", handoffs
  print "Unique ASNs:", length(asn)
  print "ICMP loss:", loss " hops (" (loss/hops*100) "%)"
  print "Countries:"
  for (c in country) print "  -", c
}
' "$FILE"
