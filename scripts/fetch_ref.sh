#!/usr/bin/env bash
# Fetch all public reference feeds for the Sydney value dashboard into raw/ref.
# Re-runnable; each step overwrites its own output. Run from Git Bash:
#   bash scripts/fetch_ref.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="$ROOT/raw/ref"; mkdir -p "$REF"
UA="property-value-dashboard (personal research)"
cget(){ curl -s --retry 3 --retry-delay 5 --max-time 180 -A "$UA" "$@"; }
log(){ printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---------- 1. RBA cash rate (F1.1) and bank mortgage rates (F5) ----------
log "RBA F1.1 / F5"
cget -o "$REF/rba_f1.1.csv" "https://www.rba.gov.au/statistics/tables/csv/f1.1-data.csv"
cget -o "$REF/rba_f5.csv"   "https://www.rba.gov.au/statistics/tables/csv/f5-data.csv"

# ---------- 2. ABS Residential Property Price Index, Greater Sydney (to 2021-Q4) ----------
log "ABS RPPI"
cget -H "Accept: text/csv" -o "$REF/abs_rppi_sydney.csv" \
  "https://data.api.abs.gov.au/rest/data/ABS,RPPI/1.2+3.1GSYD.Q?startPeriod=2003-Q3&format=csv"

# ---------- 3. BOCSAR recorded crime by suburb (monthly, 1995 on) ----------
log "BOCSAR suburb crime (12MB zip)"
cget -o "$REF/bocsar_suburb.zip" "https://bocsarblob.blob.core.windows.net/bocsar-open-data/SuburbData.zip"

# ---------- helper: page through an ArcGIS feature layer into JSON-lines ----------
# arcq <url> <where> <outFields> <outfile> [extra curl --data-urlencode args...]
arcq(){
  local url="$1" where="$2" fields="$3" out="$4"; shift 4
  local off=0 page=0; : > "$out"
  while :; do
    local tmp="$out.page"
    curl -s --retry 3 --retry-delay 5 --max-time 300 -A "$UA" -X POST "$url/query" \
      --data-urlencode "where=$where" --data-urlencode "outFields=$fields" \
      --data-urlencode "outSR=4326" --data-urlencode "f=json" \
      --data-urlencode "resultOffset=$off" --data-urlencode "resultRecordCount=2000" "$@" > "$tmp"
    local n
    n=$(perl -MJSON::PP -e '
      local $/; my $j = eval { decode_json(<STDIN>) };
      if (!$j || $j->{error}) { print STDERR "ERR: ".($j ? $j->{error}{message} : "bad json")."\n"; print "-1"; exit }
      for my $f (@{$j->{features}}) { print STDOUT "" }
      open my $o, ">>", $ARGV[0]; for my $f (@{$j->{features}}) { print $o JSON::PP->new->canonical->encode($f), "\n" } close $o;
      print scalar @{$j->{features}}; print "\n", ($j->{exceededTransferLimit} ? "MORE" : "DONE");
    ' "$out" < "$tmp")
    local cnt=$(echo "$n" | head -1) more=$(echo "$n" | tail -1)
    rm -f "$tmp"
    page=$((page+1)); off=$((off+cnt))
    [ "$cnt" = "-1" ] && { log "  page $page failed"; break; }
    [ "$more" = "MORE" ] && [ "$cnt" -gt 0 ] || break
  done
  log "  $(wc -l < "$out") features -> $(basename "$out")"
}

SP="https://portal.spatial.nsw.gov.au/server/rest/services"
# Greater Sydney bounding box (lon/lat)
SYD='{"xmin":150.55,"ymin":-34.20,"xmax":151.40,"ymax":-33.40,"spatialReference":{"wkid":4326}}'
BBOX=(--data-urlencode "geometry=$SYD" --data-urlencode "geometryType=esriGeometryEnvelope" --data-urlencode "inSR=4326" --data-urlencode "spatialRel=esriSpatialRelIntersects")

# ---------- 4. Train and metro stations (all NSW, 582) ----------
log "Stations"
arcq "$SP/NSW_FOI_Transport_Facilities/FeatureServer/1" "1=1" "generalname,operationalstatus" "$REF/stations.jsonl"

# ---------- 5. Schools: primary (0), combined (1), high (2) ----------
log "Schools"
for L in 0 1 2; do
  arcq "$SP/NSW_FOI_Education_Facilities/FeatureServer/$L" "1=1" "generalname,classsubtype,operationalstatus" "$REF/schools_$L.jsonl"
done

# ---------- 6. Suburb polygons within the Sydney box (generalised to ~40m) ----------
log "Suburb boundaries"
arcq "$SP/NSW_Administrative_Boundaries_Theme/FeatureServer/2" "1=1" "suburbname,postcode" "$REF/suburbs.jsonl" \
  "${BBOX[@]}" --data-urlencode "maxAllowableOffset=0.0004" --data-urlencode "geometryPrecision=5"

# ---------- 7. Parks: land zoned RE1 Public Recreation (NSW Planning Portal), centroids + area ----------
log "Parks (RE1 zoning)"
arcq "https://mapprod3.environment.nsw.gov.au/arcgis/rest/services/Planning/EPI_Primary_Planning_Layers/MapServer/2" \
  "SYM_CODE='RE1'" "LAY_CLASS,SYM_CODE,LGA_NAME" "$REF/parks.jsonl" \
  "${BBOX[@]}" --data-urlencode "returnGeometry=true" --data-urlencode "maxAllowableOffset=0.0005" --data-urlencode "geometryPrecision=5"

# ---------- 8. ABS Census 2021 population by suburb (SAL), NSW ----------
log "Census population by SAL"
cget -H "Accept: text/csv" -o "$REF/census_pop_sal.csv" "https://data.api.abs.gov.au/rest/data/ABS,C21_G01_SAL/3.P_1..SAL.1?format=csv"
cget -H "Accept: application/vnd.sdmx.structure+json" -o "$REF/census_sal_codes.json" "https://data.api.abs.gov.au/rest/codelist/ABS/CL_SAL_2021"

log "done"
