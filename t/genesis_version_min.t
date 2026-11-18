#!/usr/bin/env perl
# Coverage for the Genesis version the kit declares. kit.yml's
# genesis_version_min has to be at least as high as the highest version any
# hook asks for through check_minimum_genesis_version, because Genesis checks
# kit.yml before it runs a hook, and a lower value lets an older Genesis start
# a deploy that a hook then refuses halfway through.
#
# Needs nothing beyond perl.

use v5.20;
use warnings;
use FindBin;
use Test::More;

my $kit = "$FindBin::Bin/..";

# parse - split a version such as 3.1.0-rc.20 into a sortable list. A release
# sorts after its own release candidates.
sub parse {
	my ($v) = @_;
	my ($core, $pre) = split /-/, $v, 2;
	my @n = split /\./, $core;
	my $rc = defined $pre && $pre =~ /(\d+)\s*$/ ? $1 : undef;
	return (@n, defined $pre ? 0 : 1, $rc // 0);
}

sub newer {
	my ($x, $y) = @_;
	my @x = parse($x); my @y = parse($y);
	for my $i (0 .. $#x) {
		return 1  if $x[$i] > ($y[$i] // 0);
		return -1 if $x[$i] < ($y[$i] // 0);
	}
	return 0;
}

open my $kfh, '<', "$kit/kit.yml" or die "kit.yml: $!";
my ($min) = map { /^genesis_version_min:\s*"?([^\s"#]+)"?/ ? $1 : () } <$kfh>;
close $kfh;
ok(defined $min, 'kit.yml declares genesis_version_min');

my ($highest, $where) = ('0.0.0', '');
my @files = glob("$kit/hooks/*.pm");
ok(@files > 0, 'the kit has hooks to check');
for my $file (@files) {
	open my $fh, '<', $file or die "$file: $!";
	while (<$fh>) {
		next unless /check_minimum_genesis_version\(\s*['"]([^'"]+)['"]\s*\)/;
		my $required = $1;
		($highest, $where) = ($required, $file =~ s{.*/}{}r)
			if newer($required, $highest) > 0;
	}
	close $fh;
}
ok($where ne '', 'at least one hook checks a minimum Genesis version');

cmp_ok(newer($min // '0', $highest), '>=', 0,
	"genesis_version_min ($min) covers the highest hook requirement ($highest, $where)");

done_testing;
