#!/usr/bin/env perl
# Unit-level coverage for the cf-haproxy-ca feature in
# Genesis::Hook::Blueprint::Blacksmith: the overlay that hands the broker the
# CF deployment's self-signed haproxy CA must only appear when the feature is
# named, must read the CA from the vault_base the CF exodus record names, must
# merge after ocfp/cf-integration.yml whatever the feature order, must bail
# when the exodus record is missing, and must be refused without
# cf-integration.
#
# Calls the hook's subs directly against a minimal mock $self, so it needs
# the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib, the same
# as hooks/blueprint.pm itself.

use v5.20;
use warnings;
use FindBin;
use Test::More;
use File::Temp qw/tempdir/;

require "$FindBin::Bin/../hooks/blueprint.pm";

# --- minimal mocks -----------------------------------------------------------

package MockEnv;
sub new    { my ($c, %a) = @_; bless {%a}, $c }
sub name   { 'lab' }
sub lookup { my ($s, $k, $d) = @_; return $s->{lookups}{$k} // $d }
sub path   { my ($s, $p) = @_; return "$s->{root}/env/$p" }
sub kit    { $_[0] }
sub iaas   { 'pve' }
sub exodus_mount { '/secret/exodus/' }
sub exodus_lookup {
	my ($s, $key, $default, $for) = @_;
	$s->{exodus_asked} = $for;
	my $record = $s->{exodus}{$for} or return $default;
	return $record->{$key} // $default;
}

package main;

my $root = tempdir(CLEANUP => 1);

sub build_self {
	my (%opts) = @_;
	my $env = MockEnv->new(
		root    => $root,
		lookups => { 'params.bosh_environment' => 'lab-bosh' },
		exodus  => $opts{exodus} // { 'lab/cf' => { vault_base => '/secret/ocfp/cf1/lab/ocf/cf' } },
	);
	return bless {
		env_obj  => $env,
		features => $opts{features},
		files    => [],
	}, 'Genesis::Hook::Blueprint::Blacksmith';
}

{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*Genesis::Hook::Blueprint::Blacksmith::env = sub { $_[0]->{env_obj} };
	*Genesis::Hook::Blueprint::Blacksmith::kit = sub { $_[0]->{env_obj} };
}

$ENV{OCFP_IAAS} = 'pve';

sub rendered_files {
	my ($self) = @_;
	my ($iaas, $bosh, $forges) = $self->process_features;
	$self->apply_post_processing($iaas, $bosh);
	return @{ $self->{files} };
}

sub index_of {
	my ($file, @files) = @_;
	for my $i (0 .. $#files) { return $i if $files[$i] eq $file }
	return -1;
}

sub generated_content {
	my ($self, $relpath) = @_;
	open(my $fh, '<', $self->kit->path($relpath)) or die "read $relpath: $!";
	local $/;
	return <$fh>;
}

my $overlay = 'ocfp/dynamic/cf-haproxy-ca.yml';

# --- feature on --------------------------------------------------------------

subtest 'feature on' => sub {
	for my $order (
		[qw/ocfp valkey cf-integration cf-haproxy-ca/],
		[qw/ocfp valkey cf-haproxy-ca cf-integration/],
	) {
		my $self = build_self(features => $order);
		eval { $self->validate_blacksmith_features };
		is($@, '', "validation accepts [@$order]");

		my @files = eval { rendered_files($self) };
		is($@, '', "rendering succeeds for [@$order]");
		my $ca  = index_of($overlay, @files);
		my $api = index_of('ocfp/cf-integration.yml', @files);
		ok($ca >= 0, "cf-haproxy-ca overlay is added for [@$order]");
		ok($api >= 0, "cf-integration overlay is added for [@$order]");
		ok($ca > $api, "cf-haproxy-ca overlay merges after cf-integration for [@$order]");

		is($self->env->{exodus_asked}, 'lab/cf', 'vault_base is read from the sibling cf exodus record');
		like(generated_content($self, $overlay),
			qr{cf_cacert: \(\( vault "secret/ocfp/cf1/lab/ocf/cf/haproxy_ca:certificate" \)\)},
			"overlay references haproxy_ca:certificate under the exodus vault_base for [@$order]");
	}
};

# --- feature off -------------------------------------------------------------

subtest 'feature off' => sub {
	my $self = build_self(features => [qw/ocfp valkey cf-integration/], exodus => {});
	eval { $self->validate_blacksmith_features };
	is($@, '', 'validation accepts cf-integration without cf-haproxy-ca');

	my @files = eval { rendered_files($self) };
	is($@, '', 'rendering succeeds without any cf exodus record');
	ok(index_of('ocfp/cf-integration.yml', @files) >= 0, 'cf-integration overlay is still added');
	is(index_of($overlay, @files), -1, 'cf-haproxy-ca overlay is not added');
	is(scalar(grep { /haproxy/ } @files), 0, 'nothing haproxy related reaches the manifest');
	ok(!defined($self->env->{exodus_asked}), 'the cf exodus record is not consulted');
};

# --- feature on, cf not deployed yet -----------------------------------------

subtest 'missing cf exodus record' => sub {
	my $self = build_self(features => [qw/ocfp valkey cf-integration cf-haproxy-ca/], exodus => {});
	eval { rendered_files($self) };
	like($@, qr/cf-haproxy-ca/, 'bails when the cf exodus record is missing');
	like($@, qr{lab-cf}, 'names the cf deployment it looked for');
	like($@, qr{/secret/exodus/lab/cf}, 'names the exodus path it looked for');
	like($@, qr/vault_base/, 'names the missing key');

	$self = build_self(
		features => [qw/ocfp valkey cf-integration cf-haproxy-ca/],
		exodus   => { 'lab/cf' => { api_domain => 'api.lab' } },
	);
	eval { rendered_files($self) };
	like($@, qr/vault_base/, 'bails when the exodus record has no vault_base');
};

# --- feature without cf-integration -----------------------------------------

subtest 'feature without cf-integration' => sub {
	my $self = build_self(features => [qw/external-bosh valkey cf-haproxy-ca/]);
	eval { $self->validate_blacksmith_features };
	like($@, qr/cf-haproxy-ca.*requires.*cf-integration/s,
		'bails with a message naming the missing cf-integration feature');
};

done_testing;
