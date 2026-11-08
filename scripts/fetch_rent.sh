#!/usr/bin/env bash
# Rents and postcode price history for the yield table.
#  1. NSW Fair Trading rental bond lodgements (monthly xlsx, every bond lodged: postcode, dwelling type, bedrooms, weekly rent)
#     -> raw/ref/rent/rent.csv (last ~14 months)
#  2. DCJ Rent and Sales Report, sales tables by postcode (quarterly xlsx, June 2017 quarter onward)
#     -> raw/ref/dcj/dcj_sales.csv (quarter, postcode, dwelling type, median $, sales count)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; REF="$ROOT/raw/ref"; mkdir -p "$REF/rent" "$REF/dcj"
UA="property-value-dashboard (personal research)"
cget(){ curl -s -L --retry 3 --retry-delay 5 --max-time 300 -A "$UA" "$@"; }
log(){ printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }
X2C="$ROOT/scripts/xlsx2csv.pl"

# ---------- 1. rental bond lodgements ----------
log "rental bond lodgement index"
cget -o "$REF/rent/index.html" "https://www.nsw.gov.au/housing-and-construction/rental-forms-surveys-and-data/rental-bond-data"
cut=$(date -d '-14 months' +%Y-%m 2>/dev/null || date -v-14m +%Y-%m)
grep -oi 'href="[^"]*lodgements[^"]*\.xlsx"' "$REF/rent/index.html" | sed 's/href=//;s/"//g' | grep -vi 'year' | sort -u | while read -r u; do
  d=$(echo "$u" | grep -o 'noindex/[0-9]\{4\}-[0-9]\{2\}' | cut -d/ -f2); [ -n "$d" ] && [ "$d" \< "$cut" ] && continue
  f="$REF/rent/$(basename "$u")"; [ -s "$f" ] && continue
  case "$u" in http*) url="$u";; *) url="https://www.nsw.gov.au$u";; esac
  cget -o "$f" "$url" && log "  $(basename "$f") $(stat -c %s "$f" 2>/dev/null || stat -f %z "$f")B"
done
{ echo "date,postcode,type,beds,rent"
  for f in "$REF"/rent/*lodgements*.xlsx; do perl "$X2C" "$f" | perl -F, -ane 'next unless $F[0]=~/^\d{5}$/ && $F[1]=~/^\d{4}$/; my @t=gmtime(($F[0]-25569)*86400); printf "%04d-%02d-%02d,%s,%s,%s,%d\n",$t[5]+1900,$t[4]+1,$t[3],$F[1],$F[2],$F[3],$F[4]'; done
} | sort -u > "$REF/rent/rent.csv"
log "  $(($(wc -l < "$REF/rent/rent.csv")-1)) bond rows, months: $(cut -d, -f1 "$REF/rent/rent.csv" | cut -c1-7 | sort -u | grep -v date | tr '\n' ' ')"

# ---------- 2. DCJ sales tables by postcode ----------
log "DCJ sales tables"
cget -o "$REF/dcj/current.html" "https://www.dcj.nsw.gov.au/about-us/families-and-communities-statistics/housing-rent-and-sales/rent-and-sales-report.html"
cget -o "$REF/dcj/previous.html" "https://www.dcj.nsw.gov.au/about-us/families-and-communities-statistics/housing-rent-and-sales/previous-rent-and-sales-reports.html"
cat "$REF/dcj/current.html" "$REF/dcj/previous.html" | grep -oi 'href="[^"]*sales[^"]*\.xlsx"' | sed 's/href=//;s/"//g' | grep -vi 'metro-lga\|rent-tables\|rent_tables' | sort -u | while read -r u; do
  f="$REF/dcj/$(basename "$u")"; [ -s "$f" ] && continue
  case "$u" in http*) url="$u";; *) url="https://www.dcj.nsw.gov.au$u";; esac
  cget -o "$f" "$url" && log "  $(basename "$f")"
done
{ echo "quarter,postcode,type,median,n"
  for f in "$REF"/dcj/*.xlsx; do
    sn=$(unzip -p "$f" xl/workbook.xml | perl -ne 'my $i=0; while(/<sheet [^>]*name="([^"]*)"/g){ $i++; if(lc($1) eq "postcode"){ print $i; last } }')
    [ -z "$sn" ] && { log "  no Postcode sheet in $(basename "$f")"; continue; }
    perl "$X2C" "$f" "$sn" | perl -ne '
      our ($q,$mi,$ni); my %M=(january=>1,february=>2,march=>3,april=>4,may=>5,june=>6,july=>7,august=>8,september=>9,october=>10,november=>11,december=>12);
      my @c=(); while (/\G(?:"((?:[^"]|"")*)"|([^,\n]*))(?:,|\n|$)/g){ push @c, defined $1?$1:$2; last if pos()>=length }
      if (!$q) { my $l=join(" ",@c);
        if ($l=~/Reporting period:.*?(?:-|to)\s*([A-Za-z]+)\s+(\d{4})/i || $l=~/([A-Za-z]+)\s+Quarter\s+(\d{4})/i) { my $m=$M{lc $1}; $q=$2."Q".int(($m-1)/3+1) if $m } }
      if (($c[0]//"") eq "Postcode") { ($mi,$ni)=(undef,undef); for my $i (0..$#c){ $mi=$i if !defined $mi && $c[$i]=~/^Median Sales Price/i; $ni=$i if !defined $ni && $c[$i]=~/^Sales\s*No/i } next }
      next unless $q && defined $mi && $c[0]=~/^\d{4}$/ && ($c[1]//"")=~/^(Total|Non Strata|Strata)$/;
      my $m=$c[$mi]//""; $m=~s/,//g; next unless $m=~/^\d+(\.\d+)?$/; my $n=defined $ni ? ($c[$ni]//"") : ""; $n=~s/,//g; $n="" unless $n=~/^\d+$/;
      printf "%s,%s,%s,%d,%s\n",$q,$c[0],$c[1],$m*1000,$n'
  done
} | sort -u > "$REF/dcj/dcj_sales.csv"
log "  $(($(wc -l < "$REF/dcj/dcj_sales.csv")-1)) rows; quarters: $(cut -d, -f1 "$REF/dcj/dcj_sales.csv" | sort -u | grep -v quarter | tr '\n' ' ')"
