#!/usr/bin/env bash
# Commute to Central Station (Sydney) from each suburb's centroid.
#  - Driving: OSRM public router (free-flow minutes and km). The page applies a peak-hour factor.
#  - Public transport: Transport for NSW Trip Planner API, arrive 09:00 next Monday (needs TFNSW_API_KEY,
#    free at https://opendata.transport.nsw.gov.au). Without a key the PT columns stay empty.
# Output data/commute.csv; skipped when younger than 90 days (FORCE_COMMUTE=1 to redo).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; REF="$ROOT/raw/ref"; D="$ROOT/data"; mkdir -p "$D"
OUT="$D/commute.csv"; log(){ printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }
if [ -s "$OUT" ] && [ -z "$(find "$OUT" -mtime +90)" ] && [ "${FORCE_COMMUTE:-0}" != 1 ]; then
  if [ -n "${TFNSW_API_KEY:-}" ] && [ "$(awk -F, 'NR>1 && $7!=""' "$OUT" | wc -l)" -eq 0 ]; then log "commute.csv has no PT data and a key is set - refetching"; else log "commute.csv is current - skip"; echo "::notice title=Commute::TFNSW_API_KEY $( [ -n "${TFNSW_API_KEY:-}" ] && echo present || echo MISSING ); using cached commute.csv"; exit 0; fi; fi
CEN_LON=151.2069; CEN_LAT=-33.8832
# next Monday (local), 09:00 arrival
NEXTMON=$(date -d 'next monday' +%Y%m%d 2>/dev/null || date -v+mon +%Y%m%d)
perl -MJSON::PP -ne 'my $j=eval{decode_json($_)} or next; my $pc=$j->{attributes}{postcode}; next unless ($pc>=2000&&$pc<=2234)||($pc>=2555&&$pc<=2574)||($pc>=2745&&$pc<=2770); my $k=uc $j->{attributes}{suburbname}; my @r=sort { @$b<=>@$a } @{$j->{geometry}{rings}||[]}; next unless @r; my ($x,$y,$n)=(0,0,0); for (@{$r[0]}){ $x+=$_->[0]; $y+=$_->[1]; $n++ } my $sz=scalar @{$r[0]}; if (!$S{$k} || $sz>$S{$k}[2]){ $S{$k}=[sprintf("%.5f",$x/$n),sprintf("%.5f",$y/$n),$sz,$pc] } END { print join(",",$_,$S{$_}[3],$S{$_}[1],$S{$_}[0]),"\n" for sort keys %S }' "$REF/suburbs.jsonl" > "$D/_centroids.csv"
log "$(wc -l < "$D/_centroids.csv") suburbs"
echo "key,pc,lat,lon,drive_min,drive_km,pt_min,pt_dep,pt_changes" > "$OUT.tmp"
i=0; while IFS=, read -r k pc lat lon; do i=$((i+1))
  r=$(curl -s --max-time 30 "https://router.project-osrm.org/route/v1/driving/$lon,$lat;$CEN_LON,$CEN_LAT?overview=false" | perl -MJSON::PP -e 'local $/; my $j=eval{decode_json(<STDIN>)}; my $rt=$j && $j->{routes} ? $j->{routes}[0] : undef; printf "%s,%s", $rt?sprintf("%.1f",$rt->{duration}/60):"", $rt?sprintf("%.1f",$rt->{distance}/1000):""')
  pt=",,"
  if [ -n "${TFNSW_API_KEY:-}" ]; then
    pt=$(curl -s --max-time 60 -H "Authorization: apikey $TFNSW_API_KEY" "https://api.transport.nsw.gov.au/v1/tp/trip?outputFormat=rapidJSON&coordOutputFormat=EPSG%3A4326&depArrMacro=arr&itdDate=$NEXTMON&itdTime=0900&type_origin=coord&name_origin=${lon}%3A${lat}%3AEPSG%3A4326&type_destination=coord&name_destination=${CEN_LON}%3A${CEN_LAT}%3AEPSG%3A4326&calcNumberOfTrips=6&TfNSWTR=true" \
      | perl -MJSON::PP -MPOSIX -e 'local $/; my $j=eval{decode_json(<STDIN>)}; my $best; for my $t (@{$j->{journeys}||[]}){ my @l=@{$t->{legs}||[]}; next unless @l; my $dep=$l[0]{origin}{departureTimeEstimated}||$l[0]{origin}{departureTimePlanned}; my $arr=$l[-1]{destination}{arrivalTimeEstimated}||$l[-1]{destination}{arrivalTimePlanned}; next unless $dep && $arr;
          my $p=sub{ my ($y,$mo,$d,$h,$mi,$s)=$_[0]=~/(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/; POSIX::mktime($s,$mi,$h,$d,$mo-1,$y-1900) }; my $mins=($p->($arr)-$p->($dep))/60; my $ch=scalar(grep { ($_->{transportation}{product}{class}//100)!=100 && ($_->{transportation}{product}{class}//99)!=99 } @l)-1; $ch=0 if $ch<0;
          if (!$best || $mins<$best->[0]){ $best=[$mins,$dep,$ch] } }
        if ($best){ my ($h,$mi)=$best->[1]=~/T(\d+):(\d+)/; my $lm=($h*60+$mi+11*60)%1440; printf "%.0f,%02d:%02d,%d", $best->[0], int($lm/60), $lm%60, $best->[2] } else { print ",," }')
  fi
  echo "$k,$pc,$lat,$lon,$r,$pt" >> "$OUT.tmp"
  [ $((i % 100)) -eq 0 ] && log "  $i done"; sleep 0.4
done < "$D/_centroids.csv"
mv -f "$OUT.tmp" "$OUT"; rm -f "$D/_centroids.csv"
log "wrote $(($(wc -l < "$OUT")-1)) rows -> data/commute.csv (PT $( [ -n "${TFNSW_API_KEY:-}" ] && echo on || echo off: no TFNSW_API_KEY))"
echo "::notice title=Commute::TFNSW_API_KEY $( [ -n "${TFNSW_API_KEY:-}" ] && echo present || echo MISSING ); PT journeys found: $(awk -F, "NR>1 && \!=\"\"" "$OUT" | wc -l) of $(($(wc -l < "$OUT")-1))"
