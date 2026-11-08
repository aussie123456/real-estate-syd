#!/usr/bin/perl
# Reads VG .DAT text on STDIN, writes CSV rows for Greater Sydney sales on STDOUT.
# Record B layout (2001+ format): B;district;propid;salecounter;download;propname;unit;houseno;street;locality;
#   postcode;area;areatype;contract;settlement;price;zoning;nature;purpose;stratalot;component;salecode;pct;dealing;
use strict; use warnings;
sub syd { my $p=shift; return 0 unless $p =~ /^\d{4}$/;
  return ($p>=2000 && $p<=2234) || ($p>=2555 && $p<=2574) || ($p>=2745 && $p<=2770); }
sub csvq { my $s=shift; $s =~ s/"/""/g; return ($s =~ /[,"]/) ? "\"$s\"" : $s; }
while (my $l = <STDIN>) {
  next unless substr($l,0,2) eq 'B;';
  $l =~ s/[\r\n]+$//;
  my @f = split /;/, $l, -1;
  next if @f < 24;
  my ($dist,$propid,$unit,$houseno,$street,$loc,$pc,$area,$atype,$contract,$settle,$price,$zone,$nature,$purpose,$strata,$dealing)
    = @f[1,2,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23];
  next unless syd($pc);
  next unless $price =~ /^\d+(\.\d+)?$/ && $price > 0;
  my $sqm = '';
  if ($area ne '' && $area =~ /^[\d.]+$/) { $sqm = ($atype eq 'H') ? $area*10000 : $area; $sqm = sprintf('%.0f',$sqm); }
  $_ = uc for ($street,$loc,$purpose);
  print join(',', map { csvq($_) } ($propid,$dist,$unit,$houseno,$street,$loc,$pc,$sqm,$contract,$settle,$price,$zone,$nature,$purpose,$strata,$dealing)), "\n";
}
