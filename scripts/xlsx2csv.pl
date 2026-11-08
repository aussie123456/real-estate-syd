#!/usr/bin/perl
# Minimal .xlsx -> CSV (first sheet or sheet N): perl scripts/xlsx2csv.pl file.xlsx [sheetN]
use strict; use warnings;
my ($f,$n)=@ARGV; $n||=1; die "usage" unless $f;
my $ss=`unzip -p "$f" xl/sharedStrings.xml 2>/dev/null`; my @s; while($ss=~/<si>(.*?)<\/si>/gs){ my $x=$1; my $t=join'', $x=~/<t[^>]*>([^<]*)<\/t>/g; $t=~s/&amp;/&/g;$t=~s/&lt;/</g;$t=~s/&gt;/>/g;$t=~s/&quot;/"/g; push @s,$t }
my $sh=`unzip -p "$f" xl/worksheets/sheet$n.xml`; 
while($sh=~/<row[^>]*>(.*?)<\/row>/gs){ my $r=$1; my %c;
  while($r=~/<c r="([A-Z]+)\d+"([^>]*?)(?:\/>|>(.*?)<\/c>)/gs){ my ($col,$attr,$in)=($1,$2,$3//''); my $v=''; if($in=~/<v>([^<]*)<\/v>/){ $v=$1; $v=$s[$v] if $attr=~/t="s"/ } elsif($in=~/<t[^>]*>([^<]*)<\/t>/){ $v=$1 } $v=~s/[
]+/ /g; $v=~s/"/""/g; $c{$col}=$v }
  my @cols=sort { length($a)<=>length($b) || $a cmp $b } keys %c; next unless @cols; my $last=$cols[-1]; my @out; my $col='A';
  while(1){ my $v=$c{$col}//''; push @out,($v=~/[,"\n]/?"\"$v\"":$v); last if $col eq $last; $col++ } print join(',',@out),"\n" }
