#!/usr/bin/env perl
# Guards the contract between the BOSH kit and this kit. The BOSH kit's
# blacksmith-integration and credhub addons publish five CredHub connection
# keys in the director's exodus record, this kit's wiring file reads them, and
# hooks/blueprint.pm checks that every one is present before it includes the
# wiring. A rename in either kit breaks this test before it breaks a deploy.
#
# The BOSH kit comes from BOSH_KIT_DIR, which defaults to the sibling kits/bosh
# checkout. The test fails, and never skips, when that directory is missing.
#
# Needs the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib, the
# same as hooks/blueprint.pm itself.

use v5.20;
use warnings;
use FindBin;
use Cwd qw/abs_path/;
use Test::More;

require "$FindBin::Bin/../hooks/blueprint.pm";

my @blueprint_keys = do { no warnings "once"; sort @Genesis::Hook::Blueprint::Blacksmith::CREDHUB_EXODUS_KEYS };

# The five keys the plan names, spelled out once more here so that a change to
# the blueprint array alone is caught.
my @expected = sort qw(
	credhub_url
	blacksmith_credhub_client_id
	blacksmith_credhub_client_secret
	blacksmith_credhub_ca_cert
	blacksmith_credhub_director_name
);

sub slurp {
	my ($path) = @_;
	open(my $fh, '<', $path) or die "cannot read $path: $!\n";
	local $/;
	return <$fh>;
}

# The keys a file publishes: the indented keys of its top-level exodus block.
sub exodus_block_keys {
	my ($path) = @_;
	my (%keys, $in);
	for my $line (split /\n/, slurp($path)) {
		if ($line =~ /^exodus:\s*$/)      { $in = 1; next }
		if ($line =~ /^\S/)               { $in = 0; next }
		next unless $in;
		next if $line =~ /^\s*#/;
		$keys{$1} = 1 if $line =~ /^\s+([A-Za-z0-9_]+):/;
	}
	return %keys;
}

subtest 'the blueprint array holds the five keys' => sub {
	is_deeply(\@blueprint_keys, \@expected, 'the array matches the exodus table');
};

subtest 'the wiring file reads exactly those keys' => sub {
	my $wiring = abs_path("$FindBin::Bin/../manifests/addons/credhub-cleanup.yml");
	ok(defined($wiring) && -f $wiring, 'the wiring file exists');
	my %read;
	for my $line (split /\n/, slurp($wiring)) {
		next if $line =~ /^\s*#/;
		$read{$1} = 1 while $line =~ /vault\s+meta\.bosh\.exodus\s+":([A-Za-z0-9_]+)"/g;
	}
	is_deeply([sort keys %read], \@blueprint_keys,
		'the keys the wiring file dereferences equal the blueprint array');
};

subtest 'the BOSH kit publishes every key' => sub {
	my $dir = $ENV{BOSH_KIT_DIR} || "$FindBin::Bin/../../bosh";
	ok(-d $dir, "the BOSH kit directory $dir exists (set BOSH_KIT_DIR to the BOSH kit checkout)")
		or return;
	my %published;
	for my $addon (qw/blacksmith-integration credhub/) {
		my $file = "$dir/overlay/addons/$addon.yml";
		ok(-f $file, "$file exists") or next;
		%published = (%published, exodus_block_keys($file));
	}
	for my $key (@blueprint_keys) {
		ok($published{$key}, "the BOSH kit publishes $key in the director's exodus record");
	}
};

done_testing;
