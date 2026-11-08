#!/usr/bin/env bash
# Look up every Valuer General property ID in data/sales.csv against the NSW Spatial Services
# Property layer (same ID system) to get parcel centroid lon/lat and polygon area.
# Results are cached in data/geo.csv; only new IDs are requested on re-runs.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; D="$ROOT/data"
URL="https://portal.spatial.nsw.gov.au/server/rest/services/NSW_Land_Parcel_Property_Theme/FeatureServer/12/query"
UA="property-value-dashboard (personal research)"
[ -f "$D/sales.csv" ] || { echo "data/sales.csv missing - run parse_vg.sh first"; exit 1; }
[ -f "$D/geo.csv" ] || echo "propid,lon,lat,parcel_sqm,address,valnettype" > "$D/geo.csv"
log(){ printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

# ids to fetch = ids in sales not yet in geo (and not in the miss list)
touch "$D/geo_missing.txt"
perl -F, -ane 'print "$F[0]\n" if $.>1 && $F[0]=~/^\d+$/' "$D/sales.csv" | sort -u > "$D/_ids_all.txt"
cut -d, -f1 "$D/geo.csv" | sort -u > "$D/_ids_have.txt"
sort -u "$D/geo_missing.txt" > "$D/_ids_miss.txt"
comm -23 "$D/_ids_all.txt" "$D/_ids_have.txt" | comm -23 - "$D/_ids_miss.txt" > "$D/_ids_todo.txt"
TODO=$(wc -l < "$D/_ids_todo.txt"); log "$TODO property IDs to geocode (batches of 400)"

split -l 400 -d -a 5 "$D/_ids_todo.txt" "$D/_batch_"
i=0; n=$(ls "$D"/_batch_* 2>/dev/null | wc -l)
for b in "$D"/_batch_*; do
  [ -f "$b" ] || break
  i=$((i+1)); ids=$(paste -sd, "$b")
  curl -s --retry 3 --retry-delay 10 --max-time 300 -A "$UA" -X POST "$URL" \
    --data-urlencode "where=propid IN ($ids)" --data-urlencode "outFields=propid,address,Shape__Area,valnetpropertytype" \
    --data-urlencode "returnCentroid=true" --data-urlencode "returnGeometry=false" \
    --data-urlencode "outSR=4326" --data-urlencode "f=json" > "$b.json"
  got=$(perl -MJSON::PP -e '
    local $/; my $j = eval { decode_json(<STDIN>) }; exit 2 if !$j || $j->{error};
    open my $o, ">>", $ARGV[0]; my %seen;
    for my $f (@{$j->{features}}) { my $a=$f->{attributes}; next if $seen{$a->{propid}}++;
      (my $ad = $a->{address} // "") =~ s/,/ /g;
      printf $o "%d,%.6f,%.6f,%.0f,%s,%s\n", $a->{propid}, $f->{centroid}{x}, $f->{centroid}{y}, $a->{Shape__Area}//0, $ad, $a->{valnetpropertytype}//"" }
    close $o; print scalar(keys %seen);' "$D/geo.csv" < "$b.json")
  rc=$?
  if [ $rc -ne 0 ]; then log "  batch $i/$n failed (kept for retry)"; sleep 15; continue; fi
  # ids not returned -> missing list (cancelled / superseded property IDs)
  perl -F, -ane 'print "$F[0]\n" if $.>1' "$D/geo.csv" | sort -u > "$D/_ids_have.txt"
  comm -23 <(sort -u "$b") "$D/_ids_have.txt" >> "$D/geo_missing.txt"
  rm -f "$b" "$b.json"
  [ $((i % 25)) -eq 0 ] && log "  batch $i/$n ($(wc -l < "$D/geo.csv") geocoded)"
  sleep 0.3
done
rm -f "$D"/_ids_*.txt "$D"/_batch_*
log "done: $(($(wc -l < "$D/geo.csv")-1)) geocoded, $(sort -u "$D/geo_missing.txt" | wc -l) not found"
