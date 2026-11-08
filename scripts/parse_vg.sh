#!/usr/bin/env bash
# Parse NSW Valuer General "Property Sales Information" yearly zips (raw/vg/*.zip) into one CSV per year
# (data/sales_part_YYYY.csv), then merge every part present into data/sales.csv (Greater Sydney, de-duplicated).
# Years whose part file already exists are re-parsed only when their zip is present in raw/vg.
# Usage: bash scripts/parse_vg.sh            (all zips in raw/vg)
#        bash scripts/parse_vg.sh 2025.zip   (one file)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VG="$ROOT/raw/vg"; OUT="$ROOT/data"; TMP="$ROOT/raw/vg/_tmp"; mkdir -p "$OUT" "$TMP"
log(){ printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }
PARSER="$ROOT/scripts/parse_vg.pl"

files=("$@"); [ ${#files[@]} -eq 0 ] && files=($(cd "$VG" && ls *.zip 2>/dev/null))
for z in "${files[@]}"; do
  y="${z%.zip}"; log "== $z"
  part="$OUT/sales_part_$y.csv"; tmpart="$part.tmp"; : > "$tmpart"
  rm -rf "$TMP/$y"; mkdir -p "$TMP/$y"
  # yearly zip may hold weekly zips, or DAT files directly (older years)
  if ! unzip -q -o "$VG/$z" -d "$TMP/$y"; then log "  unzip failed"; rm -f "$tmpart"; continue; fi
  nd=$(find "$TMP/$y" -iname '*.DAT' | wc -l)
  if [ "$nd" -gt 0 ]; then find "$TMP/$y" -iname '*.DAT' -print0 | xargs -0 cat | perl "$PARSER" >> "$tmpart"; fi
  while IFS= read -r w; do unzip -p "$w" '*.DAT' 2>/dev/null | perl "$PARSER" >> "$tmpart"; done < <(find "$TMP/$y" -iname '*.zip')
  rm -rf "$TMP/$y"
  if [ -s "$tmpart" ]; then mv -f "$tmpart" "$part"; log "  $(wc -l < "$part") Sydney sale records"; else rm -f "$tmpart"; log "  no records parsed (kept previous part if any)"; fi
done

parts=("$OUT"/sales_part_*.csv)
[ -s "${parts[0]}" ] || { echo "No parsed sales. Put Valuer General yearly zips in raw/vg (see README)."; exit 1; }
log "merging ${#parts[@]} year file(s)"
{ echo "propid,district,unit,houseno,street,locality,postcode,area_sqm,contract,settlement,price,zoning,nature,purpose,strata,dealing";
  cat "${parts[@]}" | perl -F, -ane 'my $k=join("|",@F[0,8,10,15]); print unless $seen{$k}++'; } > "$OUT/sales.csv"
log "$(wc -l < "$OUT/sales.csv") rows -> data/sales.csv"
