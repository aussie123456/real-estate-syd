#!/usr/bin/env bash
# Fetch NSW Valuer General yearly "Property Sales Information" zips into raw/vg/.
# Order of attempts per year: 1) already parsed (data/sales_part_YYYY.csv) and not the current year -> skip;
# 2) direct download from the Valuer General site; 3) asset YYYY.zip on the GitHub release tagged "vg-data"
# (upload the zips there once from your browser if the site refuses scripted downloads).
# Env: VG_YEARS = "2012-2026" or "2019,2024" (blank = 2012 to current year); GH_TOKEN/GH_REPO for the release fallback.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; VG="$ROOT/raw/vg"; D="$ROOT/data"; mkdir -p "$VG" "$D"
log(){ printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }
CUR=$(date +%Y)
spec="${VG_YEARS:-2012-$CUR}"
years=()
IFS=',' read -ra parts <<< "$spec"
for p in "${parts[@]}"; do p="${p// /}"; [ -z "$p" ] && continue
  if [[ "$p" =~ ^([0-9]{4})-([0-9]{4})$ ]]; then for ((y=${BASH_REMATCH[1]}; y<=${BASH_REMATCH[2]}; y++)); do years+=("$y"); done
  elif [[ "$p" =~ ^[0-9]{4}$ ]]; then years+=("$p"); fi; done
forced=0; [ -n "${VG_YEARS:-}" ] && forced=1

ok=0; skipped=0; failed=()
for y in "${years[@]}"; do
  if [ $forced -eq 0 ] && [ "$y" -lt "$CUR" ] && [ -s "$D/sales_part_$y.csv" ]; then skipped=$((skipped+1)); continue; fi
  out="$VG/$y.zip"; rm -f "$out"
  code=$(curl -sS -L --retry 2 --max-time 900 -o "$out" -w '%{http_code}' "https://www.valuergeneral.nsw.gov.au/__psi/yearly/$y.zip" || echo 000)
  if [ "$code" = "200" ] && unzip -tq "$out" >/dev/null 2>&1; then log "$y: downloaded from Valuer General ($(du -h "$out" | cut -f1))"; ok=$((ok+1)); continue; fi
  rm -f "$out"; log "$y: site returned $code, trying release asset"
  if command -v gh >/dev/null && gh release download vg-data -p "$y.zip" -D "$VG" --clobber >/dev/null 2>&1 && unzip -tq "$out" >/dev/null 2>&1; then
    log "$y: from release vg-data ($(du -h "$out" | cut -f1))"; ok=$((ok+1)); continue; fi
  rm -f "$out"; failed+=("$y")
done
log "done: $ok downloaded, $skipped already parsed, ${#failed[@]} unavailable${failed:+ (${failed[*]})}"
[ ${#failed[@]} -gt 0 ] && echo "::warning::Valuer General files unavailable for: ${failed[*]} - upload them as assets on a release tagged vg-data"
exit 0
