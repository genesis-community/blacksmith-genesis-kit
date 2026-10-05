#!/usr/bin/env perl
# Unit-level coverage for the credhub-cleanup feature in
# Genesis::Hook::Blueprint::Blacksmith: the overlay that turns on CredHub
# cleanup of deprovisioned service instances must only appear when the
# feature is named, and the feature must be refused unless the environment
# uses an external director (external-bosh or ocfp), because the internal
# director has no CredHub cleanup target.
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
sub exodus_lookup { return $_[2] }

package main;

my $root = tempdir(CLEANUP => 1);

sub build_self {
	my (%opts) = @_;
	my $env = MockEnv->new(
		root    => $root,
		lookups => { 'params.bosh_environment' => 'lab-bosh' },
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

my $overlay = 'manifests/addons/credhub-cleanup.yml';

# --- feature on --------------------------------------------------------------

subtest 'feature on with ocfp' => sub {
	my $self = build_self(features => [qw/ocfp valkey credhub-cleanup/]);
	eval { $self->validate_blacksmith_features };
	is($@, '', 'validation accepts credhub-cleanup with ocfp');

	my @files = eval { rendered_files($self) };
	is($@, '', 'rendering succeeds');
	ok(index_of($overlay, @files) >= 0, 'credhub-cleanup overlay is added');
	ok(-f "$FindBin::Bin/../$overlay", 'the overlay file exists in the kit');
};

subtest 'feature on with external-bosh' => sub {
	my $self = build_self(features => [qw/external-bosh valkey credhub-cleanup/]);
	eval { $self->validate_blacksmith_features };
	is($@, '', 'validation accepts credhub-cleanup with external-bosh');
	my @files = eval { rendered_files($self) };
	ok(index_of($overlay, @files) >= 0, 'credhub-cleanup overlay is added');
};

# --- feature off -------------------------------------------------------------

subtest 'feature off' => sub {
	my $self = build_self(features => [qw/ocfp valkey/]);
	eval { $self->validate_blacksmith_features };
	is($@, '', 'validation accepts ocfp without credhub-cleanup');

	my @files = eval { rendered_files($self) };
	is($@, '', 'rendering succeeds');
	is(index_of($overlay, @files), -1, 'credhub-cleanup overlay is not added');
	is(scalar(grep { /credhub/ } @files), 0, 'nothing credhub related reaches the manifest');
};

# --- feature without an external director -----------------------------------

subtest 'feature without external-bosh or ocfp' => sub {
	my $self = build_self(features => [qw/aws valkey credhub-cleanup/]);
	eval { $self->validate_blacksmith_features };
	like($@, qr/credhub-cleanup.*requires.*external-bosh/s,
		'bails with a message naming the missing external-bosh feature');
	like($@, qr/no CredHub\s+cleanup target|internal director/s,
		'the message says why the internal director cannot be used');
};

# --- sweep parameter ---------------------------------------------------------

sub sweep_self {
	my ($sweep) = @_;
	my $self = build_self(features => [qw/ocfp valkey credhub-cleanup/]);
	$self->{env_obj}{lookups}{'params.credhub_cleanup.sweep'} = $sweep;
	return $self;
}

subtest 'sweep parameter' => sub {
	for my $ok ('off', 'dry-run', 'delete', 0, '') {
		my $self = sweep_self($ok);
		eval { $self->validate_blacksmith_features };
		is($@, '', "validation accepts sweep '$ok'");
	}
	my $self = sweep_self('dryrun');
	eval { $self->validate_blacksmith_features };
	like($@, qr/params\.credhub_cleanup\.sweep/, 'the message names the parameter');
	like($@, qr/'dryrun'/, 'the message shows the bad value');
	like($@, qr/off,\s+dry-run,\s+or\s+delete/, 'the message lists the accepted values');
};

done_testing;
