#!/usr/bin/env perl
# Coverage for the forge manifests (manifests/forges/{valkey,redis,rabbitmq}.yml).
# Each forge's plans job receives the broker's stemcell os and version as the
# stemcell_os and stemcell_version job properties, the version stays a quoted
# string, and an environment's plan overrides (vm_type, masters, replicas,
# instances, azs) reach the job unchanged.
#
# Needs spruce (or graft installed under that name) on PATH.

use v5.20;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

my $kit = "$FindBin::Bin/..";
my $dir = tempdir(CLEANUP => 1);

my %job = (
	valkey   => 'valkey-blacksmith-plans',
	redis    => 'redis-blacksmith-plans',
	rabbitmq => 'rabbitmq-blacksmith-plans',
);

# merge - merge a forge manifest with an environment snippet, return the
# plans job properties and the raw merged text.
my $n = 0;
sub merge {
	my ($forge, $env, @extra) = @_;
	my $envfile = "$dir/env" . $n++ . ".yml";
	open my $fh, '>', $envfile or die "$envfile: $!";
	print $fh "genesis: {env: test, bosh_env: test}\n$env";
	close $fh;
	my @files = ("$kit/manifests/forges/$forge.yml", @extra, $envfile);
	my $text = qx(spruce merge @files 2>&1);
	is($? >> 8, 0, "$forge manifest merges") or diag $text;
	my $json = qx(spruce merge @files 2>/dev/null | spruce json);
	my $doc = decode_json($json);
	my ($j) = grep { $_->{name} eq $job{$forge} } @{$doc->{instance_groups}[0]{jobs}};
	return ($j->{properties}, $text);
}

for my $forge (qw(valkey redis rabbitmq)) {
	# Nothing set: the defaults, with the version kept as a string.
	my ($p, $text) = merge($forge, "params: {}\n");
	is($p->{stemcell_os}, 'ubuntu-noble', "$forge: stemcell_os defaults to ubuntu-noble");
	is($p->{stemcell_version}, 'latest', "$forge: stemcell_version defaults to latest");

	# The broker's os and a numeric-looking version.
	($p, $text) = merge($forge, "params: {stemcell_os: ubuntu-resolute, stemcell_version: \"0.184\"}\n");
	is($p->{stemcell_os}, 'ubuntu-resolute', "$forge: stemcell_os follows params.stemcell_os");
	is($p->{stemcell_version}, '0.184', "$forge: stemcell_version follows params.stemcell_version");
	ok(!JSON::PP::is_bool($p->{stemcell_version}) && $text =~ /stemcell_version:\s+"0\.184"/,
		"$forge: stemcell_version renders as a quoted string") or diag $text;

	# The resolute feature's manifest sets the os.
	($p) = merge($forge, "params: {stemcell_version: \"0.184\"}\n", "$kit/manifests/blacksmith/resolute.yml");
	is($p->{stemcell_os}, 'ubuntu-resolute', "$forge: the resolute feature reaches the forge");
}

# The older per-forge version parameters still win for redis and rabbitmq.
for my $forge (qw(redis rabbitmq)) {
	my ($p, $text) = merge($forge, "params: {stemcell_version: \"0.184\", ${forge}_stemcell_version: \"1.1298\"}\n");
	is($p->{stemcell_version}, '1.1298', "$forge: ${forge}_stemcell_version wins over params.stemcell_version");
	like($text, qr/stemcell_version:\s+"1\.1298"/, "$forge: that version renders quoted");
}

# Plan overrides reach the forge job unchanged.
{
	my %plans = (
		valkey => {
			standalone => { name => 'standalone', limit => 7, type => 'standalone', version => 8, vm_type => 'small' },
			'cluster-3' => { name => 'cluster-3', limit => 2, type => 'cluster', version => 8, vm_type => 'small', masters => 3, replicas => 0, azs => ['z1'] },
		},
		redis => {
			standalone => { name => 'standalone', limit => 7, type => 'standalone', vm_type => 'small' },
			cluster    => { name => 'cluster', limit => 2, type => 'cluster', vm_type => 'small', masters => 3, replicas => 0, azs => ['z1'] },
		},
		rabbitmq => {
			standalone => { name => 'standalone', limit => 7, type => 'standalone', vm_type => 'small' },
			cluster    => { name => 'cluster', limit => 2, type => 'cluster', vm_type => 'small', instances => 3, azs => ['z1'] },
		},
	);
	for my $forge (qw(valkey redis rabbitmq)) {
		my $env = "params:\n  ${forge}_plans: " . JSON::PP->new->canonical->encode($plans{$forge}) . "\n";
		my ($p) = merge($forge, $env);
		is_deeply($p->{plans}, $plans{$forge}, "$forge: the env's plans reach the job unchanged");
	}
}

done_testing;
