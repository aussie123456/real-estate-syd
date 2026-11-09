#!/usr/bin/perl
# Build dashboard/data.js from data/sales.csv + data/geo.csv + raw/ref/*.
# Runs without sales data (macro + map layers only). Env overrides: SALES=, GEO=, OUT= (for test fixtures).
use strict; use warnings; use JSON::PP; use List::Util qw(sum min max first);
use File::Basename qw(dirname); use POSIX qw(strftime floor);
my $ROOT = dirname(dirname(__FILE__)); my $REF="$ROOT/raw/ref"; my $D="$ROOT/data";
my $SALES = $ENV{SALES} // "$D/sales.csv"; my $GEO = $ENV{GEO} // "$D/geo.csv";
my $OUT = $ENV{OUT} // "$ROOT/dashboard/data.js";
sub log_ { printf STDERR "%s  %s\n", strftime("%H:%M:%S", localtime), "@_" }
my $J = JSON::PP->new->canonical;

# ---------------- helpers ----------------
sub median { my @a = sort { $a <=> $b } grep { defined } @_; return undef unless @a; my $n=@a; $n%2 ? $a[$n/2] : ($a[$n/2-1]+$a[$n/2])/2 }
sub pctl { my ($p,@v)=@_; my @a = sort { $a <=> $b } @v; return undef unless @a; $a[int($p*$#a+0.5)] }
sub r2 { defined $_[0] ? sprintf('%.2f',$_[0])+0 : undef } sub r0 { defined $_[0] ? sprintf('%.0f',$_[0])+0 : undef } sub r4 { defined $_[0] ? sprintf('%.4f',$_[0])+0 : undef }
sub syd { my $p=shift; return 0 unless defined $p && $p =~ /^\d{4}$/; ($p>=2000&&$p<=2234)||($p>=2555&&$p<=2574)||($p>=2745&&$p<=2770) }
use constant PI => 3.14159265358979;
sub hav { my ($la1,$lo1,$la2,$lo2)=@_; my $r=6371; my $dl=($la2-$la1)*PI/180; my $dn=($lo2-$lo1)*PI/180;
  my $a=sin($dl/2)**2+cos($la1*PI/180)*cos($la2*PI/180)*sin($dn/2)**2; 2*$r*atan2(sqrt($a),sqrt(1-$a)) }
sub csvsplit { my $l=shift; $l =~ s/[\r\n]+$//; my @f; while ($l =~ /\G(?:"((?:[^"]|"")*)"|([^,]*))(?:,|$)/g) { my $v = defined $1 ? $1 : $2; $v =~ s/""/"/g if defined $1; push @f,$v; last if pos($l)>=length $l } @f }
sub read_jsonl { my $f=shift; open my $h,'<',$f or return (); my @r; while(<$h>){ chomp; push @r, eval { decode_json($_) } if length } close $h; @r }
my %MON=(jan=>1,feb=>2,mar=>3,apr=>4,may=>5,jun=>6,jul=>7,aug=>8,sep=>9,oct=>10,nov=>11,dec=>12);
sub ymd { my $d=shift//''; return sprintf('%04d-%02d',$3,$2) if $d=~m{^(\d{2})/(\d{2})/(\d{4})$}; return sprintf('%04d-%02d',$3,$MON{lc $2}) if $d=~m{^(\d{2})-([A-Za-z]{3})-(\d{4})$}; undef }
sub titlecase { my $s=lc shift; $s =~ s/(^|[\s\-(])(\w)/$1\u$2/g; $s =~ s/\bMc(\w)/Mc\u$1/g; $s }
# grid index for nearest-neighbour: 0.01 deg cells (~1.1km)
sub gidx { my $pts=shift; my %g; for my $p (@$pts){ push @{$g{int($p->[0]*100).",".int($p->[1]*100)}}, $p } \%g }
sub nearest { my ($g,$la,$lo)=@_; my ($best,$bd)=(undef,1e9); my ($ci,$cj)=(int($la*100),int($lo*100));
  for my $r (0..12) { for my $i ($ci-$r..$ci+$r){ for my $j ($cj-$r..$cj+$r){ next unless abs($i-$ci)==$r || abs($j-$cj)==$r;
      for my $p (@{$g->{"$i,$j"}||[]}){ my $d=hav($la,$lo,$p->[0],$p->[1]); ($best,$bd)=($p,$d) if $d<$bd } } }
    last if $bd < $r*0.9; }
  return ($best,$bd) }
my ($CBD_LAT,$CBD_LON)=(-33.8731,151.2069);  # Sydney Town Hall

# ---------------- 1. macro ----------------
log_ "macro";
my (%cash,@cashm); { open my $h,'<',"$REF/rba_f1.1.csv" or die; local $/; my $t=<$h>; $t=~s/\r/\n/g;
  for (split /\n/,$t){ my @f=split /,/; next unless $f[0] && $f[0]=~m{^(\d{2})/(\d{2})/(\d{4})$}; my $ym="$3-$2"; next unless length($f[1]//''); $cash{$ym}=$f[1]+0; push @cashm,[$ym,$f[1]+0] } }
my %mort; { open my $h,'<',"$REF/rba_f5.csv" or die; local $/; my $t=<$h>; $t=~s/\r/\n/g;
  for (split /\n/,$t){ my @f=split /,/; my $ym=ymd($f[0]) or next;
    push @{$mort{std}},[$ym,$f[3]+0] if length($f[3]//''); push @{$mort{disc}},[$ym,$f[4]+0] if length($f[4]//'');
    push @{$mort{fixed3}},[$ym,$f[6]+0] if length($f[6]//''); push @{$mort{inv_disc}},[$ym,$f[8]+0] if length($f[8]//''); } }
if (open my $h,'<',"$REF/rba_f6.csv") { local $/; my $t=<$h>; $t=~s/\r/\n/g;   # F6: rates on new loans funded in the month (closer to what a borrower pays than the F5 indicator rates)
  my ($io,$ii); for (split /\n/,$t){ if (/^Series ID/){ my @s=split /,/; for my $i (0..$#s){ $io=$i if $s[$i] eq 'FLRHOFVA'; $ii=$i if $s[$i] eq 'FLRHIFVA' } last } }   # header cells contain newlines, so locate columns by series ID
  if (defined $io && defined $ii){ for (split /\n/,$t){ my @f=split /,/; my $ym=ymd($f[0]) or next; push @{$mort{oo_new}},[$ym,$f[$io]+0] if length($f[$io]//''); push @{$mort{inv_new}},[$ym,$f[$ii]+0] if length($f[$ii]//'') } } }
my %rppi; { open my $h,'<',"$REF/abs_rppi_sydney.csv" or die; while(<$h>){ my @f=split /,/; next unless $f[5] && $f[5]=~/^\d{4}-Q\d$/; (my $q=$f[5])=~s/-//; push @{$rppi{$f[2]==2?'houses':'all'}},[$q,$f[6]+0] } }
my %cashq; { my %acc; for (@cashm){ my ($y,$m)=split /-/,$_->[0]; my $q=$y."Q".(int(($m-1)/3)+1); push @{$acc{$q}},$_->[1] } $cashq{$_}=sum(@{$acc{$_}})/@{$acc{$_}} for keys %acc }

# ---------------- 2. reference layers ----------------
log_ "reference layers";
my %sub;  # NAME => {pc, polys, lat, lon}
for my $f (read_jsonl("$REF/suburbs.jsonl")) { my $n=uc $f->{attributes}{suburbname}; my $pc=$f->{attributes}{postcode}; next unless syd($pc);
  $sub{$n} //= {name=>$n, pc=>$pc, polys=>[]}; push @{$sub{$n}{polys}}, $f->{geometry}{rings} if $f->{geometry}{rings}; }
for my $s (values %sub) { my ($sx,$sy,$n)=(0,0,0); my @big = sort { @$b <=> @$a } map { @$_ } @{$s->{polys}};
  for my $p (@{$big[0]||[]}) { $sx+=$p->[0]; $sy+=$p->[1]; $n++ } if ($n){ $s->{lon}=$sx/$n; $s->{lat}=$sy/$n } }
log_ "  ".scalar(keys %sub)." suburbs";
my %inbox = map { $_=>1 } keys %sub;
sub inbbox { my ($la,$lo)=@_; $la>-34.25 && $la<-33.35 && $lo>150.5 && $lo<151.45 }
my @stations = map { my $n=$_->{attributes}{generalname}//''; $n =~ s/ RAILWAY STATION//; [ $_->{geometry}{y}, $_->{geometry}{x}, titlecase($n) ] }
  grep { ($_->{attributes}{operationalstatus}//1)==1 && inbbox($_->{geometry}{y},$_->{geometry}{x}) } read_jsonl("$REF/stations.jsonl");
# school scores (optional, user-maintained: name,type,score,note,source)
my %sscore; if (open my $h,'<',"$REF/school_scores.csv") { my $hdr=<$h>; while(<$h>){ my @f=csvsplit($_); next unless $f[0] && length($f[2]//''); $sscore{uc $f[0]}={type=>lc($f[1]//''),score=>$f[2]+0,note=>$f[3]//'',source=>$f[4]//''} } close $h }
my (@prim,@high);
for my $L (0,1,2) { for my $f (read_jsonl("$REF/schools_$L.jsonl")) { next unless inbbox($f->{geometry}{y},$f->{geometry}{x}); my $n=$f->{attributes}{generalname}//''; my $nm=titlecase($n);
    my $sc=$sscore{uc $n}; my $pt=[$f->{geometry}{y},$f->{geometry}{x},$nm,($sc?$sc->{score}:undef)];
    push @prim,$pt if $L!=2; push @high,$pt if $L!=0 } }
my @parks; for my $f (read_jsonl("$REF/parks.jsonl")) { my $rings=$f->{geometry}{rings} or next; my ($A,$sx,$sy,$n)=(0,0,0,0);
  for my $r (@$rings){ my $a=0; for my $i (0..$#$r-1){ my ($x1,$y1)=@{$r->[$i]}; my ($x2,$y2)=@{$r->[$i+1]}; $a+=$x1*$y2-$x2*$y1; $sx+=$x1; $sy+=$y1; $n++ } $A+=abs($a)/2 }
  next unless $n; my $lat=$sy/$n; my $sqm=$A*111320*111320*cos($lat*PI/180); push @parks,[$lat,$sx/$n,$sqm] if $sqm>=3000 }
log_ "  ".scalar(@stations)." stations, ".scalar(@prim)." primary, ".scalar(@high)." high, ".scalar(@parks)." parks >=3000sqm";
my ($gst,$gpr,$ghi,$gpk)=(gidx(\@stations),gidx(\@prim),gidx(\@high),gidx(\@parks));
# census population by suburb name
my %pop; { my %code; if (open my $h,'<',"$REF/census_sal_codes.json") { local $/; my $t=<$h>; while($t=~/"id":"(\d+)","name":"([^"]+)"/g){ my ($c,$n)=($1,$2); $n=~s/ \((NSW|Vic\.|Qld|SA|WA|Tas\.|NT|ACT)\)$//; $code{$c}=uc $n } close $h }
  if (open my $h,'<',"$REF/census_pop_sal.csv") { while(<$h>){ my @f=split /,/; next unless $f[3] && $code{$f[3]}; $pop{$code{$f[3]}}=$f[7]+0 } close $h } }
# crime
log_ "crime";
my %crime; { open my $h,'-|',"unzip -p \"$REF/bocsar_suburb.zip\" SuburbData.csv" or die; my $hdr=<$h>; my @hc=csvsplit($hdr); my $last=$#hc; my $lastm=$hc[$last];
  my @r12=($last-11..$last); my @r5=($last-71..$last-60);
  while(<$h>){ my @f=csvsplit($_); my $s=uc $f[0]; next unless $inbox{$s}; my ($cat,$sc)=($f[1],$f[2]);
    my $g = ($cat eq 'Assault' || $cat eq 'Robbery' || $cat eq 'Sexual offences') ? 'v'
          : ($sc =~ /^(Break and enter dwelling|Motor vehicle theft|Steal from motor vehicle|Steal from dwelling)$/ || $cat eq 'Malicious damage to property') ? 'p' : '';
    next unless $g;
    $crime{$s}{$g}+=sum(map { $f[$_]||0 } @r12); $crime{$s}{"${g}5"}+=sum(map { $f[$_]||0 } @r5); $crime{$s}{asof}=$lastm }
  close $h }

# parcel lot sizes per suburb (NSW property layer statistics) and commute times
my (%lots,%commute); if (open my $h,'<',"$D/lots.csv") { my $hdr=<$h>; while(<$h>){ chomp; my @f=split /,/; $lots{$f[0]}={med=>$f[2]+0,avg=>$f[3]+0,n=>$f[4]+0} if $f[4] } close $h; log_ "  lots: ".scalar(keys %lots)." suburbs" }
if (open my $h,'<',"$D/commute.csv") { my $hdr=<$h>; while(<$h>){ chomp; my @f=split /,/; $commute{$f[0]}={drive_min=>length($f[4]//'')?$f[4]+0:undef, drive_km=>length($f[5]//'')?$f[5]+0:undef, pt_min=>length($f[6]//'')?$f[6]+0:undef, pt_dep=>$f[7]||undef, pt_changes=>length($f[8]//'')?$f[8]+0:undef} } close $h; log_ "  commute: ".scalar(keys %commute)." suburbs" }
# DCJ rent history: house median weekly rent (new bonds, all bedrooms) by postcode, quarterly from 2017
my (%dcjr,$dcjr_q); if (open my $h,'<',"$REF/dcj/dcj_rent.csv") { my $hdr=<$h>; while(<$h>){ chomp; my ($q,$pc,$t,$b,$m,$n)=split /,/; next unless ($t//'') eq 'House' && ($b//'') eq 'all' && ($m//0)>0; $dcjr{$pc}{$q}=$m+0; $dcjr_q=$q if !$dcjr_q || $q gt $dcjr_q } close $h; log_ "  DCJ rent history to ".($dcjr_q//'-').", ".scalar(keys %dcjr)." postcodes" }
sub dcjr_avg4 { my ($pc,$end)=@_; my @v=grep { defined } map { $dcjr{$pc}{qname($_)} } ($end-3..$end); @v>=2 ? sum(@v)/@v : undef }
# infrastructure: hand-maintained project list (raw/ref/infrastructure.csv) + TOD precincts from the Housing SEPP map layers
my %stname; for (@stations){ $stname{uc $_->[2]}=$_ }
my @infra; if (open my $h,'<',"$REF/infrastructure.csv") { my $hdr=<$h>; while(<$h>){ my @f=csvsplit($_); next unless $f[0]; my ($lat,$lon)=($f[5],$f[6]); if ((!$lat || !$lon) && $f[4]){ my $s=$stname{uc $f[4]}; ($lat,$lon)=($s->[0],$s->[1]) if $s } next unless $lat && $lon; push @infra,[$lat+0,$lon+0,$f[0],$f[1],$f[2],$f[3],($f[7]||0.5)+0] } close $h }
{ my %tc; for my $f (read_jsonl("$REF/tod_sites.jsonl")){ $tc{uc($f->{attributes}{PRECINCT}//'')}++ }
  for my $p (keys %tc){ next unless $p; my @c=map { $stname{$_} } grep { my $n=$_; $p=~/\b\Q$n\E\b/ } keys %stname; my ($s)=sort { length($b->[2])<=>length($a->[2]) } @c; next unless $s; push @infra,[$s->[0],$s->[1],"TOD precinct ".titlecase($p)." ($tc{$p} lots)",'tod','rezoned',2024,0.7] }
  for my $f (read_jsonl("$REF/tod_acc.jsonl")){ my $r=$f->{geometry}{rings} or next; my ($sx,$sy,$n)=(0,0,0); for my $ring (@$r){ for (@$ring){ $sx+=$_->[0]; $sy+=$_->[1]; $n++ } } next unless $n; (my $nm=$f->{attributes}{LABEL}//'')=~s/ Accelerated TOD Precinct//; push @infra,[$sy/$n,$sx/$n,"Accelerated TOD precinct $nm",'tod','rezoned',2024,1.0] } }
log_ "  ".scalar(@infra)." infrastructure points";
# rents: NSW rental bond lodgements, trailing 12 months, by postcode
log_ "rents";
my (%rent,$rent_asof); if (open my $h,'<',"$REF/rent/rent.csv") { my @rows; my $hdr=<$h>; while(<$h>){ chomp; my @f=split /,/; next unless ($f[1]//'')=~/^\d{4}$/ && ($f[4]//0)>0; push @rows,\@f } close $h;
  my $max=''; for (@rows){ $max=$_->[0] if $_->[0] gt $max } $rent_asof=substr($max,0,7); my ($y,$m)=split /-/,$rent_asof; my $from=sprintf('%04d-%02d',$y-1,$m);
  for (@rows){ next unless substr($_->[0],0,7) gt $from; my ($pc,$t,$b,$r)=@$_[1..4];
    if ($t eq 'H'){ push @{$rent{$pc}{h}},$r; push @{$rent{$pc}{h3}},$r if $b=~/^\d+$/ && $b==3; push @{$rent{$pc}{h4}},$r if $b=~/^\d+$/ && $b>=4 } elsif ($t eq 'F' || $t eq 'U'){ push @{$rent{$pc}{u}},$r } }
  log_ "  ".scalar(keys %rent)." postcodes, bonds to $rent_asof" }
# DCJ Rent and Sales Report: quarterly median non-strata (house) sale price by postcode
my (%dcj,$dcj_q); if (open my $h,'<',"$REF/dcj/dcj_sales.csv") { my $hdr=<$h>; while(<$h>){ chomp; my ($q,$pc,$t,$m,$n)=split /,/; next unless ($t//'') eq 'Non Strata' && ($m//0)>0; $dcj{$pc}{$q}=[$m+0,$n||0]; $dcj_q=$q if !$dcj_q || $q gt $dcj_q } close $h; log_ "  DCJ postcode price history to $dcj_q" }
sub qidx { my ($y,$q)=$_[0]=~/^(\d{4})Q(\d)$/; $y*4+$q-1 } sub qname { my $i=shift; int($i/4)."Q".($i%4+1) }
# average of the 4 quarterly medians ending at quarter index $end (needs >=2 present)
sub dcj_avg4 { my ($pc,$end)=@_; my @v=grep { defined } map { $dcj{$pc}{qname($_)} ? $dcj{$pc}{qname($_)}[0] : undef } ($end-3..$end); @v>=2 ? sum(@v)/@v : undef }

# ---------------- 3. sales ----------------
my (%geo); if (open my $h,'<',$GEO) { my $hdr=<$h>; while(<$h>){ chomp; my @f=split /,/; $geo{$f[0]}=[$f[2]+0,$f[1]+0,$f[3]+0] } close $h }
log_ "geo: ".scalar(keys %geo)." properties";
my @sales; my $maxdate=''; my $hasSales=0;
if (open my $h,'<',$SALES) { my $hdr=<$h>; my ($bad,$units)=(0,0);
  while(<$h>){ my @f=csvsplit($_); my ($propid,$dist,$unit,$hno,$street,$loc,$pc,$sqm,$contract,$settle,$price,$zone,$nature,$purpose,$strata,$dealing)=@f;
    next unless $contract && $contract=~/^(\d{4})(\d{2})(\d{2})$/; my ($y,$m)=($1,$2);
    if (length($strata//'') || length($unit//'')) { $units++; next }
    my $land = (($nature//'') eq 'V' || ($purpose//'') =~ /VACANT/) ? 1 : 0;
    next unless $land || ($nature//'') eq 'R' || ($purpose//'') =~ /RESIDEN/;
    next if ($purpose//'') =~ /FARM|SHOP|OFFICE|INDUSTR|WAREHOUSE|FACTORY|HOTEL|CHURCH|SCHOOL|CAR PARK/;
    next unless $sqm && $sqm>=120 && $sqm<=5000 && $price>=150000; my $psm=$price/$sqm; if ($psm<150 || $psm>60000){ $bad++; next }
    my $g=$geo{$propid}; my $s=uc $loc; $sub{$s} or next;
    my $q=$y."Q".(int(($m-1)/3)+1); $maxdate=$contract if $contract gt $maxdate;
    push @sales,{sub=>$s,st=>$street,hno=>$hno,date=>$contract,q=>$q,y=>$y+0,price=>$price+0,sqm=>$sqm+0,psm=>$psm,land=>$land,lat=>$g?$g->[0]:undef,lon=>$g?$g->[1]:undef,parcel=>$g?$g->[2]:undef,zone=>$zone}; }
  close $h; $hasSales = @sales>0; log_ "sales: ".scalar(@sales)." house/land, $units units skipped, $bad outliers; latest contract $maxdate";
  # drop same-property same-day duplicates (split-interest transfers) and sales far below the suburb-year median (non-arm's-length, part shares)
  my @keep;
  { my %first; for my $s (sort { $b->{price} <=> $a->{price} } @sales){ my $k=join('|',$s->{sub},$s->{st},$s->{hno},$s->{date}); next if $first{$k}++; push @keep,$s } @sales=@keep; @keep=(); }
  { my %g; push @{$g{"$_->{sub}|$_->{y}"}},$_ for grep { !$_->{land} } @sales; my %medp; my %medpsm; for my $k (keys %g){ $medp{$k}=median(map{$_->{price}}@{$g{$k}}); $medpsm{$k}=median(map{$_->{psm}}@{$g{$k}}) }
    my $drop=0; for my $s (@sales){ my $k="$s->{sub}|$s->{y}"; if (!$s->{land} && $medp{$k} && @{$g{$k}}>=5 && ($s->{price} < 0.3*$medp{$k} || $s->{psm} < 0.25*$medpsm{$k})) { $drop++; next } push @keep,$s } @sales=@keep;
    log_ "  after cleaning: ".scalar(@sales)." sales ($drop below 30% of suburb-year median removed)" } }
else { log_ "no sales file ($SALES) - building macro/map-only data" }
my ($ttm_from,$ttm_to,$prev_from); if ($hasSales){ my ($y,$m)=($maxdate=~/^(\d{4})(\d{2})/); $ttm_to="$y$m"; $ttm_from=sprintf('%04d%02d',$y-1,$m); $prev_from=sprintf('%04d%02d',$y-2,$m) }
my $asof = $hasSales ? substr($maxdate,0,4).'-'.substr($maxdate,4,2).'-'.substr($maxdate,6,2) : undef;
my $y5 = $hasSales ? substr($maxdate,0,4)-5 : 0;

# per-sale proximity for located sales in the last 5 years
log_ "proximity";
my $np=0; for my $s (@sales){ next unless defined $s->{lat} && $s->{y}>=$y5; my ($st,$ds)=nearest($gst,$s->{lat},$s->{lon}); my ($pk,$dp)=nearest($gpk,$s->{lat},$s->{lon});
  my ($pr,$dpr)=nearest($gpr,$s->{lat},$s->{lon}); my ($hi,$dhi)=nearest($ghi,$s->{lat},$s->{lon});
  @$s{qw(d_st st_name d_pk d_pr pr_name pr_score d_hi hi_name hi_score d_cbd)}=($ds,$st?$st->[2]:undef,$dp,$dpr,$pr?$pr->[2]:undef,$pr?$pr->[3]:undef,$dhi,$hi?$hi->[2]:undef,$hi?$hi->[3]:undef,hav($s->{lat},$s->{lon},$CBD_LAT,$CBD_LON)); $np++ }
log_ "  $np sales located";

# ---------------- 4. streets ----------------
my %street; for my $s (@sales){ next unless defined $s->{d_st} && !$s->{land}; my $k="$s->{sub}|$s->{st}"; my $r=$street{$k}//={sub=>$s->{sub},street=>$s->{st},n=>0,lat=>0,lon=>0,psm=>[],price=>[],sqm=>[],dst=>[],dpk=>[],dcbd=>[],dpr=>[],dhi=>[],last=>''};
  $r->{n}++; $r->{lat}+=$s->{lat}; $r->{lon}+=$s->{lon}; push @{$r->{psm}},$s->{psm}; push @{$r->{price}},$s->{price}; push @{$r->{sqm}},$s->{sqm}; push @{$r->{dst}},$s->{d_st}; push @{$r->{dpk}},$s->{d_pk}; push @{$r->{dcbd}},$s->{d_cbd}; push @{$r->{dpr}},$s->{d_pr}; push @{$r->{dhi}},$s->{d_hi}; $r->{last}=$s->{date} if $s->{date} gt $r->{last} }
my @streets; for my $r (values %street){ next if $r->{n}<3; push @streets,{sub=>$r->{sub},street=>titlecase($r->{street}),n=>$r->{n},lat=>r4($r->{lat}/$r->{n}),lon=>r4($r->{lon}/$r->{n}),med_psm=>r0(median(@{$r->{psm}})),med_price=>r0(median(@{$r->{price}})),med_lot=>r0(median(@{$r->{sqm}})),d_station=>r2(median(@{$r->{dst}})),d_park=>r2(median(@{$r->{dpk}})),d_cbd=>r2(median(@{$r->{dcbd}})),d_prim=>r2(median(@{$r->{dpr}})),d_high=>r2(median(@{$r->{dhi}})),last=>$r->{last}} }
log_ "  ".scalar(@streets)." streets with >=3 located sales in 5y";

# ---------------- 5. suburbs ----------------
log_ "suburb metrics";
my %by; push @{$by{$_->{sub}}},$_ for @sales;
# quarterly series start in 2012 (first full file year); earlier contract dates in the files are long-settlement oddities
my @quarters; if ($hasSales){ my ($y0,$y1)=(2012,substr($maxdate,0,4)); my $lq=substr($maxdate,0,4)."Q".(int((substr($maxdate,4,2)-1)/3)+1); Y: for my $y ($y0..$y1){ for my $q (1..4){ my $k="${y}Q$q"; push @quarters,$k; last Y if $k eq $lq } } }
my @sydq; { my %qs; push @{$qs{$_->{q}}},$_ for grep { !$_->{land} } @sales; for my $q (@quarters){ my $a=$qs{$q}||[]; push @sydq,[$q,r0(median(map {$_->{psm}} @$a)),r0(median(map {$_->{price}} @$a)),scalar(@$a)] } }
my @subs;
for my $name (sort keys %sub){ my $S=$sub{$name}; my $all=$by{$name}||[]; my @h=grep { !$_->{land} } @$all;
  my $o={name=>titlecase($name), key=>$name, pc=>$S->{pc}, lat=>r4($S->{lat}), lon=>r4($S->{lon}), pop=>$pop{$name}};
  my @loc=grep { defined $_->{d_st} } @h;
  if (@loc){ $o->{d_station}=r2(median(map{$_->{d_st}}@loc)); $o->{d_park}=r2(median(map{$_->{d_pk}}@loc)); $o->{d_cbd}=r2(median(map{$_->{d_cbd}}@loc)); $o->{d_prim}=r2(median(map{$_->{d_pr}}@loc)); $o->{d_high}=r2(median(map{$_->{d_hi}}@loc));
    my %c; $c{$_->{st_name}}++ for grep {$_->{st_name}} @loc; ($o->{station})=sort { $c{$b}<=>$c{$a} } keys %c;
    my %cp; $cp{$_->{pr_name}}++ for grep {$_->{pr_name}} @loc; ($o->{prim})=sort { $cp{$b}<=>$cp{$a} } keys %cp;
    my %ch; $ch{$_->{hi_name}}++ for grep {$_->{hi_name}} @loc; ($o->{high})=sort { $ch{$b}<=>$ch{$a} } keys %ch; }
  elsif (defined $S->{lat}) { my ($st,$ds)=nearest($gst,$S->{lat},$S->{lon}); my ($pk,$dp)=nearest($gpk,$S->{lat},$S->{lon}); my ($pr,$dpr)=nearest($gpr,$S->{lat},$S->{lon}); my ($hi,$dhi)=nearest($ghi,$S->{lat},$S->{lon});
    @$o{qw(d_station station d_park d_prim prim d_high high d_cbd)}=(r2($ds),$st?$st->[2]:undef,r2($dp),r2($dpr),$pr?$pr->[2]:undef,r2($dhi),$hi?$hi->[2]:undef,r2(hav($S->{lat},$S->{lon},$CBD_LAT,$CBD_LON))); $o->{centroid_based}=1 }
  $o->{prim_score}=$sscore{uc($o->{prim}//'')} ? $sscore{uc $o->{prim}}{score} : undef; $o->{high_score}=$sscore{uc($o->{high}//'')} ? $sscore{uc $o->{high}}{score} : undef;
  if (my $c=$crime{$name}){ my $p=$o->{pop}; if ($p && $p>=300){ $o->{crime_v}=r2(1000*($c->{v}//0)/$p); $o->{crime_p}=r2(1000*($c->{p}//0)/$p); $o->{crime}=r2(1000*(($c->{v}//0)+($c->{p}//0))/$p); my $c5=($c->{v5}//0)+($c->{p5}//0); $o->{crime_chg}=$c5? r2((($c->{v}//0)+($c->{p}//0))/$c5-1):undef } $o->{crime_n}=($c->{v}//0)+($c->{p}//0) }
  if ($hasSales){
    my @ttm=grep { my $d=substr($_->{date},0,6); $d gt $ttm_from && $d le $ttm_to } @h; my @prev=grep { my $d=substr($_->{date},0,6); $d gt $prev_from && $d le $ttm_from } @h;
    $o->{n_ttm}=scalar @ttm; $o->{n_land_ttm}=scalar grep { my $d=substr($_->{date},0,6); $d gt $ttm_from && $d le $ttm_to && $_->{land} } @$all; $o->{n_all}=scalar @h;
    if (@ttm){ $o->{med_psm}=r0(median(map{$_->{psm}}@ttm)); $o->{med_price}=r0(median(map{$_->{price}}@ttm)); $o->{med_lot}=r0(median(map{$_->{sqm}}@ttm)); $o->{p25}=r0(pctl(0.25,map{$_->{psm}}@ttm)); $o->{p75}=r0(pctl(0.75,map{$_->{psm}}@ttm)); $o->{lot_p75}=r0(pctl(0.75,map{$_->{sqm}}@ttm)); }
    if (@prev){ $o->{med_psm_prev}=r0(median(map{$_->{psm}}@prev)); $o->{n_prev}=scalar @prev; $o->{yoy}=($o->{med_psm}&&$o->{med_psm_prev})? r4($o->{med_psm}/$o->{med_psm_prev}-1):undef }
    my %qs; push @{$qs{$_->{q}}},$_ for @h; my (@qp,@qpr,@qn,@sm);
    for my $i (0..$#quarters){ my $q=$quarters[$i]; my $a=$qs{$q}||[]; push @qp,r0(median(map{$_->{psm}}@$a)); push @qpr,r0(median(map{$_->{price}}@$a)); push @qn,scalar @$a;
      my @pool=(@$a, ($i>0 ? @{$qs{$quarters[$i-1]}||[]} : ())); push @sm, (@pool>=8 ? median(map{$_->{psm}}@pool) : undef) }
    $o->{series}={psm=>\@qp,price=>\@qpr,n=>\@qn,sm=>[map{r0($_)}@sm]};
    my @pk=grep { defined } map { $quarters[$_]=~/^(2021|2022)Q/ ? $sm[$_] : undef } 0..$#quarters; my $cur=first { defined } reverse @sm;
    if (@pk && $cur){ $o->{peak_psm}=r0(max(@pk)); $o->{dd}=r4($cur/max(@pk)-1) }
    my @b5=grep { defined } map { $quarters[$_]=~/^${y5}Q/ ? $sm[$_] : undef } 0..$#quarters; if (@b5 && $cur){ $o->{g5}=r4($cur/(sum(@b5)/@b5)-1) }
    my (@x,@y); for my $i (2..$#quarters){ next unless defined $sm[$i] && defined $sm[$i-2] && defined $cashq{$quarters[$i]} && defined $cashq{$quarters[$i-2]}; push @y,log($sm[$i]/$sm[$i-2]); push @x,$cashq{$quarters[$i]}-$cashq{$quarters[$i-2]} }
    if (@x>=16){ my $mx=sum(@x)/@x; my $my=sum(@y)/@y; my ($sxy,$sxx,$syy)=(0,0,0); for my $i (0..$#x){ $sxy+=($x[$i]-$mx)*($y[$i]-$my); $sxx+=($x[$i]-$mx)**2; $syy+=($y[$i]-$my)**2 }
      if ($sxx>0){ $o->{beta}=r4($sxy/$sxx); $o->{r2}=$syy>0? r2($sxy**2/($sxx*$syy)):undef; $o->{nq}=scalar @x } }
    # shorter price windows (2, 3, 6 months to the latest contract date)
    for my $m (2,3,6){ my ($y,$mo)=($ttm_to=~/^(\d{4})(\d{2})$/); my $t=$y*12+$mo-1-$m; my $from=sprintf('%04d%02d',int($t/12),$t%12+1); my @w=grep { my $d=substr($_->{date},0,6); $d gt $from && $d le $ttm_to } @h;
      $o->{"n_${m}m"}=scalar @w; if (@w>=5){ $o->{"price_${m}m"}=r0(median(map{$_->{price}}@w)); $o->{"psm_${m}m"}=r0(median(map{$_->{psm}}@w)) } }
    # all-time peak on rolling 4-quarter pooled medians (>=15 sales), for $/sqm and for price; "now" = latest rolling year
    my (@sm4,@pr4); { my %qs2; push @{$qs2{$_->{q}}},$_ for @h; for my $i (0..$#quarters){ my @pool; for my $k (grep { $_>=0 } ($i-3..$i)) { push @pool, @{ $qs2{$quarters[$k]} || [] } } push @sm4,(@pool>=15? median(map{$_->{psm}}@pool):undef); push @pr4,(@pool>=15? median(map{$_->{price}}@pool):undef) } }
    my ($pk,$pkq,$pkp,$pkpq); for my $i (0..$#quarters){ if (defined $sm4[$i] && (!defined $pk || $sm4[$i]>$pk)){ $pk=$sm4[$i]; $pkq=$quarters[$i] } if (defined $pr4[$i] && (!defined $pkp || $pr4[$i]>$pkp)){ $pkp=$pr4[$i]; $pkpq=$quarters[$i] } }
    my $cur4=$sm4[-1]; my $curp4=$pr4[-1];
    if ($pk && $cur4){ $o->{peak_all}=r0($pk); $o->{peak_all_q}=$pkq; $o->{dd_all}=r4($cur4/$pk-1) } if ($pkp && $curp4){ $o->{peakp_all}=r0($pkp); $o->{peakp_all_q}=$pkpq; $o->{ddp_all}=r4($curp4/$pkp-1) }
    $o->{series}{sm4}=[map{r0($_)}@sm4]; $o->{series}{pr4}=[map{r0($_)}@pr4];
  }
  # ---- rents, DCJ postcode price, CAGRs, gross yield ----
  { my $pc=$S->{pc}; my $r=$rent{$pc};
    if ($r){ my @h=@{$r->{h}||[]}; if (@h>=10){ $o->{rent_w}=r0(median(@h)); $o->{rent_n}=scalar @h } $o->{rent3}=r0(median(@{$r->{h3}})) if @{$r->{h3}||[]}>=8; $o->{rent4}=r0(median(@{$r->{h4}})) if @{$r->{h4}||[]}>=8; $o->{rent_u}=r0(median(@{$r->{u}})) if @{$r->{u}||[]}>=10 }
    my $d=$dcj{$pc}; if ($d && $dcj_q){ my $e=qidx($dcj_q); my $now=dcj_avg4($pc,$e); if ($now){ $o->{dcj_price}=r0($now); $o->{dcj_n}=sum(map { $dcj{$pc}{qname($_)} ? $dcj{$pc}{qname($_)}[1] : 0 } ($e-3..$e));
        for my $n (3,5,10){ my $then=dcj_avg4($pc,$e-4*$n); $o->{"dcj_cagr$n"}=r4(($now/$then)**(1/$n)-1) if $then } } }
    # VG-based CAGRs: trailing-12m median price now vs the same window n years earlier (>=8 sales each)
    if ($hasSales && @h){ my %w; for my $s (@h){ my $d=substr($s->{date},0,6); for my $n (0,3,5,10){ my ($y,$m)=($ttm_to=~/^(\d{4})(\d{2})$/); my $to=sprintf('%04d%02d',$y-$n,$m); my $fr=sprintf('%04d%02d',$y-$n-1,$m); push @{$w{$n}},$s->{price} if $d gt $fr && $d le $to } }
      if (($w{0}&&@{$w{0}}>=8)){ my $now=median(@{$w{0}}); for my $n (3,5,10){ next unless $w{$n} && @{$w{$n}}>=8; $o->{"vg_cagr$n"}=r4(($now/median(@{$w{$n}}))**(1/$n)-1) } } }
    $o->{price}= ($hasSales && $o->{med_price} && ($o->{n_ttm}//0)>=5) ? $o->{med_price} : $o->{dcj_price}; $o->{price_src}= ($hasSales && $o->{med_price} && ($o->{n_ttm}//0)>=5) ? 'VG' : ($o->{dcj_price} ? 'DCJ' : undef);
    for my $n (3,5,10){ $o->{"cagr$n"}= $o->{"vg_cagr$n"} // $o->{"dcj_cagr$n"}; $o->{"cagr${n}_src"}= defined $o->{"vg_cagr$n"} ? 'VG' : defined $o->{"dcj_cagr$n"} ? 'DCJ' : undef }
    $o->{yield}= ($o->{rent_w} && $o->{price}) ? r4($o->{rent_w}*52/$o->{price}) : undef;
    if (my $l=$lots{$name}){ $o->{lot_med}=r0($l->{med}) if $l->{med}>0; $o->{lot_avg}=r0($l->{avg}) if $l->{avg}>0; $o->{lot_n}=$l->{n} }
    $o->{lot}= ($o->{med_lot} && $o->{med_lot}>0) ? $o->{med_lot} : ($o->{lot_med} && $o->{lot_med}>0) ? $o->{lot_med} : undef; $o->{lot_src}= $o->{med_lot} ? 'sales' : $o->{lot_med} ? 'parcels' : undef;
    if (my $c=$commute{$name}){ @$o{qw(drive_min drive_km pt_min pt_dep pt_changes)}=@$c{qw(drive_min drive_km pt_min pt_dep pt_changes)} }
    # rent history (DCJ, house median by postcode): growth and change since this suburb's price peak
    if ($dcjr_q && $dcjr{$pc}){ my $e=qidx($dcjr_q); my $now=dcjr_avg4($pc,$e); if ($now){ $o->{rent_dcj}=r0($now); $o->{rent_dcj_q}=$dcjr_q; my $t3=dcjr_avg4($pc,$e-12); $o->{rent_cagr3}=r4(($now/$t3)**(1/3)-1) if $t3; my $t5=dcjr_avg4($pc,$e-20); $o->{rent_cagr5}=r4(($now/$t5)**(1/5)-1) if $t5;
        if ($o->{peakp_all_q}){ my $tp=dcjr_avg4($pc,qidx($o->{peakp_all_q})); $o->{rent_since_peak}=r4($now/$tp-1) if $tp } } }
    # infrastructure score: committed/under-construction projects and TOD precincts within 3 km (linear decay), recent ones at half weight
    if (defined $S->{lat}){ my ($sc,@near)=(0); for my $p (@infra){ my $d=hav($S->{lat},$S->{lon},$p->[0],$p->[1]); next if $d>5; push @near,[$d,$p]; my $w=$p->[6]*max(0,1-$d/3); $sc+= $p->[4] eq 'recent' ? 0.5*$w : $w }
      $o->{infra}=r2($sc); my @nn=sort { $a->[0]<=>$b->[0] } @near; @nn=@nn[0..2] if @nn>3; $o->{infra_near}=[map { [r2($_->[0]),$_->[1][2],$_->[1][4],$_->[1][5]] } @nn] } }
  push @subs,$o }
# distance-ring curve: ln(med_psm) ~ a + b*d + c*d^2 across suburbs with n_ttm>=10; resid = cheap/expensive for its ring
my @curve; if ($hasSales){ my @r=grep { $_->{med_psm} && ($_->{n_ttm}//0)>=10 && defined $_->{d_cbd} } @subs;
  if (@r>=20){ my ($n,$sx,$sx2,$sx3,$sx4,$sy,$sxy,$sx2y)=(0)x8; for (@r){ my $x=$_->{d_cbd}; my $y=log($_->{med_psm}); $n++; $sx+=$x; $sx2+=$x**2; $sx3+=$x**3; $sx4+=$x**4; $sy+=$y; $sxy+=$x*$y; $sx2y+=$x*$x*$y }
    my @A=([$n,$sx,$sx2],[$sx,$sx2,$sx3],[$sx2,$sx3,$sx4]); my @b=($sy,$sxy,$sx2y);
    for my $i (0..2){ my $p=$A[$i][$i]; $_/=$p for @{$A[$i]}; $b[$i]/=$p; for my $k (0..2){ next if $k==$i; my $f=$A[$k][$i]; $A[$k][$_]-=$f*$A[$i][$_] for 0..2; $b[$k]-=$f*$b[$i] } }
    @curve=map { r4($_) } @b;
    for (@subs){ next unless $_->{med_psm} && defined $_->{d_cbd}; my $x=$_->{d_cbd}; my $fit=exp($b[0]+$b[1]*$x+$b[2]*$x*$x); $_->{fit_psm}=r0($fit); $_->{resid}=r4(log($_->{med_psm}/$fit)) }
    log_ "  ring curve: ln psm = ".join(" ",@curve) } }
# Sydney-wide drawdown from the all-time peak (2-quarter average of quarterly median $/sqm), relative drawdown and rent re-rating per suburb
my ($syd_dd,$syd_pk,$syd_pkq); if ($hasSales && @sydq){ my @v=map { $_->[1] } @sydq; my @p; for my $i (0..$#v){ my @pool=grep { defined } map { $v[$_] } grep { $_>=0 } ($i-3..$i); push @p,(@pool==4? sum(@pool)/@pool : undef) }   # rolling 4-quarter average of quarterly medians
  my $cur=$p[-1]; for my $i (0..$#p){ if (defined $p[$i] && (!defined $syd_pk || $p[$i]>$syd_pk)){ $syd_pk=$p[$i]; $syd_pkq=$quarters[$i] } } $syd_dd=($syd_pk && $cur)? $cur/$syd_pk-1 : undef;
  for (@subs){ $_->{rel_dd}=r4($_->{dd_all}-$syd_dd) if defined $_->{dd_all} && defined $syd_dd; $_->{rerate}=r4($_->{ddp_all}-$_->{rent_since_peak}) if defined $_->{ddp_all} && defined $_->{rent_since_peak} }
  log_ sprintf("  Sydney pooled \$/sqm peak %s (%s), now %+.1f%%", r0($syd_pk), $syd_pkq, 100*$syd_dd) if defined $syd_dd }
# gap to neighbours: ln(suburb $/sqm / inverse-distance-weighted mean $/sqm of suburbs within 4 km). Negative = cheaper than its neighbours.
{ my @v=grep { $_->{med_psm} && ($_->{n_ttm}//0)>=10 && defined $_->{lat} } @subs; for my $s (@v){ my ($num,$den)=(0,0); for my $t (@v){ next if $t==$s; my $d=hav($s->{lat},$s->{lon},$t->{lat},$t->{lon}); next if $d>4 || $d<0.1; my $w=1/$d; $num+=$w*log($t->{med_psm}); $den+=$w } $s->{gap}=r4(log($s->{med_psm})-$num/$den) if $den>0 } }
# z-score components (clipped +-2.5); sign chosen so higher = better for a buyer
sub zs { my ($key,$sign,$xf)=@_; my @v=grep { defined $_->[1] } map { [$_, (defined $_->{$key} ? $xf->($_->{$key}) : undef)] } @subs; return unless @v>=10;
  my $m=sum(map{$_->[1]}@v)/@v; my $sd=sqrt(sum(map{($_->[1]-$m)**2}@v)/@v)||1; for (@v){ my $z=$sign*($_->[1]-$m)/$sd; $z=2.5 if $z>2.5; $z=-2.5 if $z<-2.5; $_->[0]{comp}{$key}=r2($z) } }
zs('resid',-1,sub{$_[0]}); zs('d_station',-1,sub{log($_[0]+0.2)}); zs('d_cbd',-1,sub{$_[0]}); zs('d_park',-1,sub{log($_[0]+0.1)}); zs('crime',-1,sub{log($_[0]+0.5)}); zs('dd',-1,sub{$_[0]}); zs('beta',1,sub{$_[0]}); zs('d_prim',-1,sub{log($_[0]+0.2)}); zs('d_high',-1,sub{log($_[0]+0.2)}); zs('prim_score',1,sub{$_[0]}); zs('high_score',1,sub{$_[0]}); zs('lot',1,sub{log($_[0])}); zs('yield',1,sub{$_[0]}); zs('drive_min',-1,sub{$_[0]}); zs('pt_min',-1,sub{$_[0]});
zs('rel_dd',-1,sub{$_[0]}); zs('rerate',-1,sub{$_[0]}); zs('gap',-1,sub{$_[0]}); zs('infra',1,sub{$_[0]});
for my $o (@subs){ my $c=$o->{comp}//{};
  my $sch; my $mode='distance';
  if (defined $c->{prim_score} || defined $c->{high_score}) { my @v=grep{defined}($c->{prim_score},$c->{high_score}); $sch=r2(sum(@v)/@v); $mode='score' }
  elsif (defined $c->{d_prim} && defined $c->{d_high}) { $sch=r2(0.5*$c->{d_prim}+0.5*$c->{d_high}) }
  # rate-driven discount: fell more than Sydney from its own peak, fell more than its rents (re-rating), and a negative beta; falls back to the 2021-22 drawdown
  my $rates; { my @v=grep{defined}(($c->{rel_dd} // $c->{dd}), $c->{rerate}, $c->{beta}); $rates=r2(sum(@v)/@v) if @v }
  $o->{score}={ value=>$c->{resid}, transport=>(defined $c->{d_station}&&defined $c->{d_cbd})? r2(0.6*$c->{d_station}+0.4*$c->{d_cbd}):undef,
    schools=>$sch, schools_mode=>$mode, parks=>$c->{d_park}, safety=>$c->{crime}, rates=>$rates, lot=>$c->{lot}, yield=>$c->{yield}, commute=>($c->{pt_min} // $c->{drive_min}), infra=>$c->{infra}, gap=>$c->{gap} };
  delete $o->{comp} }

# ---------------- 6. recent sales + geo + output ----------------
my @recent; if ($hasSales){ my ($y,$m)=($maxdate=~/^(\d{4})(\d{2})/); my $from=sprintf('%04d%02d',$y-2,$m);
  for my $s (sort { $b->{date} cmp $a->{date} } @sales){ next unless substr($s->{date},0,6) gt $from; push @recent,[$s->{sub},titlecase($s->{st}),$s->{hno},$s->{date},$s->{price},$s->{sqm},r0($s->{psm}),(defined $s->{lat}? (r4($s->{lat}),r4($s->{lon})):(undef,undef)),$s->{land}?1:0,$s->{zone}] } }
my @feat; for my $name (sort keys %sub){ my $S=$sub{$name}; my @polys=@{$S->{polys}}; next unless @polys; my $g = @polys==1 ? {type=>'Polygon',coordinates=>$polys[0]} : {type=>'MultiPolygon',coordinates=>\@polys}; push @feat,{type=>'Feature',properties=>{key=>$name},geometry=>$g} }
my $crime_asof; for (values %crime){ $crime_asof=$_->{asof}; last }
my $out={ built=>strftime("%Y-%m-%d %H:%M",localtime), refresh_url=>$ENV{REFRESH_URL}, rent_asof=>$rent_asof, dcj_q=>$dcj_q, inv_rate=>($mort{inv_new} && @{$mort{inv_new}} ? $mort{inv_new}[-1][1] : $mort{inv_disc} && @{$mort{inv_disc}} ? $mort{inv_disc}[-1][1] : undef), oo_rate=>($mort{oo_new} && @{$mort{oo_new}} ? $mort{oo_new}[-1][1] : $mort{disc} && @{$mort{disc}} ? $mort{disc}[-1][1] : undef), rate_src=>($mort{inv_new} && @{$mort{inv_new}} ? 'RBA F6 new loans funded, variable, '.$mort{inv_new}[-1][0] : 'RBA F5 indicator'), hasSales=>($hasSales?JSON::PP::true:JSON::PP::false), asof=>$asof, ttm_from=>$ttm_from, n_sales=>scalar @sales, n_geo=>scalar(grep{defined $_->{lat}}@sales), crime_asof=>$crime_asof, school_scores=>scalar(keys %sscore), quarters=>\@quarters, curve=>\@curve, cashq=>\%cashq, syd_dd=>(defined $syd_dd? r4($syd_dd):undef), syd_peak=>r0($syd_pk), syd_peak_q=>$syd_pkq, rent_hist_q=>$dcjr_q, n_infra=>scalar(@infra),
  macro=>{cash=>\@cashm, mort=>\%mort, rppi=>\%rppi, syd=>\@sydq}, suburbs=>\@subs, streets=>[sort { $a->{sub} cmp $b->{sub} || $a->{street} cmp $b->{street} } @streets], sales=>\@recent,
  points=>{stations=>[map{[r4($_->[0]),r4($_->[1]),$_->[2]]}@stations], prim=>[map{[r4($_->[0]),r4($_->[1]),$_->[2],$_->[3]]}@prim], high=>[map{[r4($_->[0]),r4($_->[1]),$_->[2],$_->[3]]}@high]},
  geo=>{type=>'FeatureCollection',features=>\@feat} };
open my $o,'>',$OUT or die "$OUT: $!"; print $o "window.PV = ", $J->encode($out), ";\n"; close $o;
log_ "wrote $OUT (".int((-s $OUT)/1024)." KB): ".scalar(@subs)." suburbs, ".scalar(@streets)." streets, ".scalar(@recent)." recent sales";
