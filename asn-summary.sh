#!/usr/bin/env bash
set -euo pipefail

# Produce per-ASN ingress/egress summary from traceroute TSV.
# Input: TSV with header; columns 5-9 used (asn, org, country, rtt, city).
FILE="$1"

awk -F'\t' '
NR == 1 { next }        # skip header
$5 == "" { next }      # skip rows without ASN

{
  asn = $5
  org = $6
  rtt = $4
  city = $9
  country = $7

  if (asn != prev_asn) {
    # Close previous ASN block when ASN changes.
    if (prev_asn != "") {
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%.1f\t%.1f\t%.1f\n",
        prev_asn,
        prev_org,
        ingress_city,
        ingress_country,
        egress_city,
        egress_country,
        ingress_rtt,
        prev_rtt,
        (prev_rtt - ingress_rtt)
    }

    # Start tracking ingress for new ASN.
    ingress_city = city
    ingress_country = country
    ingress_rtt = rtt
    prev_asn = asn
    prev_org = org
  }

  # Always update egress as we move through the path.
  egress_city = city
  egress_country = country
  prev_rtt = rtt
}

END {
  if (prev_asn != "") {
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%.1f\t%.1f\t%.1f\n",
      prev_asn,
      prev_org,
      ingress_city,
      ingress_country,
      egress_city,
      egress_country,
      ingress_rtt,
      prev_rtt,
      (prev_rtt - ingress_rtt)
  }
}
' "$FILE"
