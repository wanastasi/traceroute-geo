# traceroute-geo

Small set of scripts to run a single-probe traceroute, enrich each hop with
basic geolocation/ASN information, cache lookups, and produce simple
summaries.

Files
- `collect.sh`: runs `traceroute -q 1 -w 1 -m 20 -n`, looks up hop IPs via
	`ipinfo.io`, caches results in `cache/ip.tsv`, and emits a TSV stream.
- `summary.sh`: computes per-trace RTT statistics, ASN handoffs, and country
	counts from a traceroute TSV.
- `asn-summary.sh`: aggregates ingress/egress per ASN along the path.
- `trgeo.sh`: orchestrator that runs `collect.sh`, saves raw output to `tmp/`,
	and prints summaries.

Cache and tmp handling
- `cache/` is included in the repository and stores `ip.tsv` with cached
	`ipinfo.io` lookups. This avoids repeated API requests.
- `tmp/` is included but empty by default; runtime trace outputs are written
	there. The repository tracks `tmp/.gitkeep` so the directory exists but its
	runtime contents are ignored via `.gitignore`.

Usage
1. Make scripts executable if needed:

```bash
chmod +x collect.sh summary.sh asn-summary.sh trgeo.sh
```

2. Run a trace and save output + summaries:

```bash
./trgeo.sh example.com
```

3. Or run just collection and inspect rows live:

```bash
./collect.sh example.com | tee tmp/trgeo-example-$(date +%s).tsv
```

Notes
- The scripts use `ipinfo.io` for lookups; ensure network access and be mindful
	of rate limits for the service.
- Private/bogon addresses are short-circuited and not enriched.
