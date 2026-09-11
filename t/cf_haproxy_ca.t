#!/usr/bin/env perl
# Unit-level coverage for the cf-haproxy-ca feature in
# Genesis::Hook::Blueprint::Blacksmith: the overlay that hands the broker the
# CF deployment's self-signed haproxy CA must only appear when the feature is
# named, must merge after ocfp/cf-integration.yml whatever the feature order,
# and must be refused without cf-integration.
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
sub lookup { my ($s, $k, $d) = @_; return $s->{lookups}{$k} // $d }
sub path   { my ($s, $p) = @_; return "$s->{root}/$p" }
sub kit    { $_[0] }
sub iaas   { 'pve' }

package main;

my $empty_root = tempdir(CLEANUP => 1);

sub build_self {
	my (@features) = @_;
	my $env = MockEnv->new(
		root    => $empty_root,
		lookups => { 'params.bosh_environment' => 'lab-bosh' },
	);
	return bless {
		env_obj  => $env,
		features => \@features,
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

# --- feature on --------------------------------------------------------------

subtest 'feature on' => sub {
	for my $order (
		[qw/ocfp valkey cf-integration cf-haproxy-ca/],
		[qw/ocfp valkey cf-haproxy-ca cf-integration/],
	) {
		my $self = build_self(@$order);
		eval { $self->validate_blacksmith_features };
		is($@, '', "validation accepts [@$order]");

		my @files = rendered_files($self);
		my $ca  = index_of('ocfp/cf-haproxy-ca.yml', @files);
		my $api = index_of('ocfp/cf-integration.yml', @files);
		ok($ca >= 0, "cf-haproxy-ca overlay is added for [@$order]");
		ok($api >= 0, "cf-integration overlay is added for [@$order]");
		ok($ca > $api, "cf-haproxy-ca overlay merges after cf-integration for [@$order]");
	}
};

# --- feature off -------------------------------------------------------------

subtest 'feature off' => sub {
	my $self = build_self(qw/ocfp valkey cf-integration/);
	eval { $self->validate_blacksmith_features };
	is($@, '', 'validation accepts cf-integration without cf-haproxy-ca');

	my @files = rendered_files($self);
	ok(index_of('ocfp/cf-integration.yml', @files) >= 0, 'cf-integration overlay is still added');
	is(index_of('ocfp/cf-haproxy-ca.yml', @files), -1, 'cf-haproxy-ca overlay is not added');
	is(scalar(grep { /haproxy/ } @files), 0, 'nothing haproxy related reaches the manifest');
};

# --- feature without cf-integration -----------------------------------------

subtest 'feature without cf-integration' => sub {
	my $self = build_self(qw/external-bosh valkey cf-haproxy-ca/);
	eval { $self->validate_blacksmith_features };
	like($@, qr/cf-haproxy-ca.*requires.*cf-integration/s,
		'bails with a message naming the missing cf-integration feature');
};

done_testing;
