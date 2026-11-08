#!/usr/bin/env bash
# Median / average residential parcel size per suburb from the NSW Spatial Services Property layer
# (valnetpropertytype 2 = NORMAL, i.e. non-strata; parcels 150-5000 sqm). One statistics query per suburb polygon.
# Output data/lots.csv (key,pc,med_sqm,avg_sqm,n). Skipped when the file is younger than 90 days (slow: ~10 s per suburb, run 8-wide).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; REF="$ROOT/raw/ref"; D="$ROOT/data"; mkdir -p "$D"
OUT="$D/lots.csv"; log(){ printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }
if [ -s "$OUT" ] && [ -z "$(find "$OUT" -mtime +90)" ] && [ "${FORCE_LOTS:-0}" != 1 ]; then log "lots.csv is current ($(($(wc -l < "$OUT")-1)) suburbs) - skip"; exit 0; fi
URL="https://portal.spatial.nsw.gov.au/server/rest/services/NSW_Land_Parcel_Property_Theme/FeatureServer/12/query"
TMP="$D/_lots"; rm -rf "$TMP"; mkdir -p "$TMP"
# one job file per suburb feature (Sydney postcodes only)
perl -MJSON::PP -ne 'my $j=eval{decode_json($_)} or next; my $pc=$j->{attributes}{postcode}; next unless ($pc>=2000&&$pc<=2234)||($pc>=2555&&$pc<=2574)||($pc>=2745&&$pc<=2770); my $k=uc $j->{attributes}{suburbname}; next unless $j->{geometry}{rings}; (my $f=$k)=~s/[^A-Z0-9]+/_/g; open my $o,">>","'"$TMP"'/$f.$pc.geom"; print $o JSON::PP->new->encode({rings=>$j->{geometry}{rings},spatialReference=>{wkid=>4326}}),"\n"; close $o' "$REF/suburbs.jsonl"
n=$(ls "$TMP"/*.geom | wc -l); log "$n suburbs to query"
one(){ f="$1"; base=$(basename "$f" .geom); k="${base%.*}"; pc="${base##*.}"; k="${k//_/ }"; i=0
  while IFS= read -r geom; do i=$((i+1))
    curl -s --retry 2 --max-time 180 -X POST "$URL" --data-urlencode "geometry=$geom" --data-urlencode "geometryType=esriGeometryPolygon" --data-urlencode "inSR=4326" --data-urlencode "spatialRel=esriSpatialRelContains" \
      --data-urlencode "where=valnetpropertytype=2 AND Shape__Area>=150 AND Shape__Area<=5000" \
      --data-urlencode 'outStatistics=[{"statisticType":"percentile_cont","onStatisticField":"Shape__Area","outStatisticFieldName":"med","statisticParameters":{"value":0.5}},{"statisticType":"avg","onStatisticField":"Shape__Area","outStatisticFieldName":"avg"},{"statisticType":"count","onStatisticField":"Shape__Area","outStatisticFieldName":"n"}]' \
      --data-urlencode "f=json" | perl -MJSON::PP -e 'local $/; my $j=eval{decode_json(<STDIN>)}; my $a=$j && $j->{features}[0] ? $j->{features}[0]{attributes} : {}; printf "%s,%s,%s,%s,%s\n", $ARGV[0], $ARGV[1], $a->{med}//"", $a->{avg}//"", $a->{n}//0' "$k" "$pc"
  done < "$f" > "$f.out"; }
export -f one; export URL
ls "$TMP"/*.geom | xargs -P 8 -I{} bash -c 'one "$@"' _ {}
# aggregate multi-polygon suburbs: n-weighted average, median from the largest polygon
{ echo "key,pc,med_sqm,avg_sqm,n"; cat "$TMP"/*.out | perl -F, -ane 'chomp; my ($k,$pc,$m,$a,$n)=@F; next unless $n>0; my $r=$S{"$k|$pc"}//={k=>$k,pc=>$pc,n=>0,sa=>0,med=>undef,bn=>0}; $r->{n}+=$n; $r->{sa}+=$a*$n; if ($n>$r->{bn}){ $r->{bn}=$n; $r->{med}=$m } END { for (sort keys %S){ my $r=$S{$_}; printf "%s,%s,%.0f,%.0f,%d\n",$r->{k},$r->{pc},$r->{med},$r->{sa}/$r->{n},$r->{n} } }'; } > "$OUT"
rm -rf "$TMP"; log "wrote $(($(wc -l < "$OUT")-1)) suburbs -> data/lots.csv"
