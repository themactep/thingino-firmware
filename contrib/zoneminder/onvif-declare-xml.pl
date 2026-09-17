#!/usr/bin/perl
# ZoneMinder's ONVIF control module builds a SOAP envelope that starts with a
# newline and carries no XML declaration. Thingino's onvif_simple_server (mxml)
# rejects such a body as malformed, so every PTZ command fails with HTTP 500.
#
# Prepending the declaration makes the document unambiguously well formed and
# is valid for any ONVIF server, not just Thingino. Build-time only.

use strict;
use warnings;

my $file = '/usr/share/perl5/ZoneMinder/Control/onvif.pm';

open(my $fh, '<', $file) or die "open $file: $!";
local $/;
my $src = <$fh>;
close($fh);

my $needle = "my \$msg = '\n    <s:Envelope xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\">";
my $repl = "my \$msg = '<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n    <s:Envelope xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\">";

my $count = ($src =~ s/\Q$needle\E/$repl/);
die "onvif.pm: pattern not found, upstream layout changed\n" unless $count;

open(my $out, '>', $file) or die "write $file: $!";
print $out $src;
close($out);

print "onvif.pm: added XML declaration ($count)\n";
