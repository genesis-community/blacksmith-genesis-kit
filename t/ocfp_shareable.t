#!/usr/bin/env perl
# Coverage for the shareable parameter under ocfp. The base manifest reads
# params.shareable, so ocfp must honor that documented name, and it must keep
# reading the older params.blacksmith_sharable spelling as a fallback so that
# existing environments keep their setting. The expression is taken from
# ocfp/meta.yml itself, so the test follows the file rather than a copy of it.
#
# Needs spruce on PATH.

use v5.20;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

my $kit  = "$FindBin::Bin/..";
my $dir  = tempdir(CLEANUP => 1);

open my $meta, '<', "$kit/ocfp/meta.yml" or die "ocfp/meta.yml: $!";
my ($expr) = map { /^\s+shareable:\s+(\(\(.*\)\))\s*$/ ? $1 : () } <$meta>;
close $meta;
ok(defined $expr, "ocfp/meta.yml defines blacksmith.shareable");

my $n = 0;
sub shareable {
	my ($params) = @_;
	my $file = "$dir/case" . $n++ . ".yml";
	open my $fh, '>', $file or die "$file: $!";
	print $fh "params: $params\n";
	print $fh "meta:\n  blacksmith:\n    shareable: $expr\n";
	close $fh;
	my $json = qx(spruce merge $file 2>/dev/null | spruce json);
	is($? >> 8, 0, "merge succeeds for params $params") or return;
	my $doc = decode_json($json);
	return $doc->{meta}{blacksmith}{shareable};
}

is(shareable('{}'), JSON::PP::false, "shareable defaults to false when nothing is set");
is(shareable('{shareable: true}'), JSON::PP::true, "ocfp honors the documented params.shareable");
is(shareable('{blacksmith_sharable: true}'), JSON::PP::true, "ocfp still reads the older params.blacksmith_sharable");

done_testing;
