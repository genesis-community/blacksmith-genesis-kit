#!/usr/bin/env perl
# Unit-level coverage for the CredHub cleanup wiring in
# Genesis::Hook::Blueprint::Blacksmith. Cleanup is on by default for every
# environment with an external director (external-bosh or ocfp), and the
# blueprint wires it from that director's exodus record only when the record
# holds all five connection keys. When a key is missing the blueprint wires
# nothing and warns by name. The skip-credhub-cleanup feature, and an
# internal director that has no CredHub to clean, get an overlay that turns
# the cleanup off. The old credhub-cleanup feature name is deprecated.
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
	my ($s, $key, $default, $slug) = @_;
	push @{$s->{exodus_slugs}}, $slug;
	my $v = $s->{exodus}{$key};
	return defined($v) ? $v : $default;
}

package main;

my $root = tempdir(CLEANUP => 1);

my %exodus = (
	credhub_url                      => 'https://10.0.0.6:8844',
	blacksmith_credhub_client_id     => 'blacksmith_credhub',
	blacksmith_credhub_client_secret => 'sekrit',
	blacksmith_credhub_ca_cert       => "-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----\n",
	blacksmith_credhub_director_name => 'lab-bosh',
);

my @warnings;

sub build_self {
	my (%opts) = @_;
	my $env = MockEnv->new(
		root         => $root,
		lookups      => { 'params.bosh_environment' => 'lab-bosh' },
		exodus       => $opts{exodus} // {%exodus},
		exodus_slugs => [],
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
	for my $pkg (qw/Genesis::Hook::Blueprint Genesis::Hook::Blueprint::Blacksmith/) {
		*{"${pkg}::warning"} = sub { push @warnings, sprintf(shift, @_) };
	}
}

$ENV{OCFP_IAAS} = 'pve';

# Validation settles the feature list (the deprecated name drops out of it),
# so a render always follows a validation, as the hook does.
sub rendered_files {
	my ($self) = @_;
	$self->validate_blacksmith_features;
	my ($iaas, $bosh, $forges) = $self->process_features;
	$self->apply_post_processing($iaas, $bosh);
	return @{ $self->{files} };
}

sub index_of {
	my ($file, @files) = @_;
	for my $i (0 .. $#files) { return $i if $files[$i] eq $file }
	return -1;
}

sub slurp {
	my ($path) = @_;
	open(my $fh, '<', $path) or die "cannot read $path: $!\n";
	local $/;
	return <$fh>;
}

my $wiring = 'manifests/addons/credhub-cleanup.yml';
my $off    = 'manifests/addons/credhub-cleanup-off.yml';
my @keys   = do { no warnings "once"; @Genesis::Hook::Blueprint::Blacksmith::CREDHUB_EXODUS_KEYS };

sub reset_warnings { @warnings = () }

# --- the key list -------------------------------------------------------------

subtest 'the blueprint requires all five exodus keys' => sub {
	is_deeply([sort @keys], [sort keys %exodus],
		'the key array holds exactly the five keys the BOSH kit publishes');
};

# --- on by default -----------------------------------------------------------

subtest 'ocfp with every key gets the wiring and no feature name' => sub {
	reset_warnings();
	my $self = build_self(features => [qw/ocfp valkey/]);
	my @files = eval { rendered_files($self) };
	is($@, '', 'rendering succeeds');
	ok(index_of($wiring, @files) >= 0, 'the wiring overlay is added');
	is(index_of($off, @files), -1, 'the off overlay is not added');
	ok(-f "$FindBin::Bin/../$wiring", 'the wiring file exists in the kit');
	is(scalar(@warnings), 0, 'nothing is warned about');
	is_deeply([ grep { $_ ne 'lab/bosh' } @{ $self->{env_obj}{exodus_slugs} } ], [],
		'every exodus key is read from the director record at <env>/bosh');
};

subtest 'external-bosh with every key gets the wiring' => sub {
	reset_warnings();
	my $self = build_self(features => [qw/external-bosh valkey/]);
	my @files = eval { rendered_files($self) };
	is($@, '', 'rendering succeeds');
	ok(index_of($wiring, @files) >= 0, 'the wiring overlay is added');
	is(index_of($off, @files), -1, 'the off overlay is not added');
	is(scalar(@warnings), 0, 'nothing is warned about');
};

# --- a missing key ------------------------------------------------------------

for my $missing (@keys) {
	subtest "ocfp without $missing wires nothing and names the key" => sub {
		reset_warnings();
		my %partial = %exodus;
		delete $partial{$missing};
		my $self = build_self(features => [qw/ocfp valkey/], exodus => \%partial);
		my @files = eval { rendered_files($self) };
		is($@, '', 'rendering succeeds');
		is(index_of($wiring, @files), -1, 'the wiring overlay is not added');
		is(index_of($off, @files), -1, 'the off overlay is not added');
		is(scalar(grep { /credhub/ } @files), 0, 'nothing credhub related reaches the manifest');
		my $text = join("\n", @warnings);
		like($text, qr/\b\Q$missing\E\b/, 'the warning names the missing key');
		for my $other (grep { $_ ne $missing } @keys) {
			unlike($text, qr/\b\Q$other\E\b/, "the warning does not name $other");
		}
		like($text, qr/#Y\{/, 'the warning is yellow');
		like($text, qr/on but unconfigured|unconfigured/i, 'the warning says cleanup is unconfigured');
		like($text, qr/BOSH kit/, 'the warning points at the BOSH kit');
		like($text, qr/redeploy/i, 'the warning says the director needs a redeploy');
		like($text, qr/delet\w+ nothing/i, 'the warning says the broker deletes nothing');
	};
}

subtest 'a blank key counts as missing' => sub {
	reset_warnings();
	my $self = build_self(
		features => [qw/ocfp valkey/],
		exodus   => { %exodus, blacksmith_credhub_client_secret => '  ' },
	);
	my @files = eval { rendered_files($self) };
	is(index_of($wiring, @files), -1, 'the wiring overlay is not added');
	like(join("\n", @warnings), qr/blacksmith_credhub_client_secret/, 'the warning names the key');
};

subtest 'several missing keys are all named in one warning' => sub {
	reset_warnings();
	my $self = build_self(features => [qw/ocfp valkey/], exodus => {});
	rendered_files($self);
	my @cleanup = grep { /credhub_url/ } @warnings;
	is(scalar(@cleanup), 1, 'one warning carries the list');
	like($cleanup[0], qr/\b\Q$_\E\b/, "it names $_") for @keys;
};

# --- opting out ---------------------------------------------------------------

subtest 'skip-credhub-cleanup gets the off overlay' => sub {
	reset_warnings();
	my $self = build_self(features => [qw/ocfp valkey skip-credhub-cleanup/]);
	my @files = eval { rendered_files($self) };
	is($@, '', 'validation accepts the feature and rendering succeeds');
	ok(index_of($off, @files) >= 0, 'the off overlay is added');
	is(index_of($wiring, @files), -1, 'the wiring overlay is not added');
	is(scalar(@warnings), 0, 'nothing is warned about');
	ok(-f "$FindBin::Bin/../$off", 'the off file exists in the kit');
};

subtest 'skip-credhub-cleanup wins when the keys are missing' => sub {
	reset_warnings();
	my $self = build_self(features => [qw/ocfp valkey skip-credhub-cleanup/], exodus => {});
	my @files = rendered_files($self);
	ok(index_of($off, @files) >= 0, 'the off overlay is added');
	is(scalar(@warnings), 0, 'no missing-key warning is printed');
};

subtest 'an internal director gets the off overlay' => sub {
	reset_warnings();
	my $self = build_self(features => [qw/aws valkey/]);
	my @files = eval { rendered_files($self) };
	is($@, '', 'rendering succeeds');
	is(scalar(grep { $_ eq $off } @files), 1, 'the off overlay is added once');
	is(index_of($wiring, @files), -1, 'the wiring overlay is not added');
	is(scalar(@warnings), 0, 'nothing is warned about');
};

subtest 'an internal director with the skip feature gets the off overlay once' => sub {
	reset_warnings();
	my $self = build_self(features => [qw/aws valkey skip-credhub-cleanup/]);
	my @files = rendered_files($self);
	is(scalar(grep { $_ eq $off } @files), 1, 'the off overlay is added once');
};

# --- the deprecated feature name ----------------------------------------------

subtest 'credhub-cleanup is deprecated and still validates' => sub {
	for my $features ([qw/ocfp valkey credhub-cleanup/], [qw/external-bosh valkey credhub-cleanup/]) {
		reset_warnings();
		my $self = build_self(features => $features);
		my @files = eval { rendered_files($self) };
		is($@, '', "validation accepts credhub-cleanup with $features->[0]");
		ok(index_of($wiring, @files) >= 0, 'the wiring overlay is still added');
		my @dep = grep { /credhub-cleanup/ } @warnings;
		is(scalar(@dep), 1, 'one deprecation message is printed');
		like($dep[0], qr/now the default/, 'it says the feature is now the default');
		like($dep[0], qr/can be removed/, 'it says the name can be removed');
	}
};

subtest 'credhub-cleanup on an internal director no longer errors' => sub {
	reset_warnings();
	my $self = build_self(features => [qw/aws valkey credhub-cleanup/]);
	my @files = eval { rendered_files($self) };
	is($@, '', 'validation accepts the deprecated name');
	ok(index_of($off, @files) >= 0, 'the off overlay is added');
};

# --- the shipped wiring and off files -----------------------------------------

subtest 'the wiring file states its defaults on its own lines' => sub {
	my $text = slurp("$FindBin::Bin/../$wiring");
	like($text, qr/^\s*enabled:\s+true\s*$/m, 'enabled: true stands on its own line');
	like($text, qr/^\s*sweep:\s+\(\(\s*grab\s+params\.credhub_cleanup\.sweep\s+\|\|\s+"dry-run"\s*\)\)\s*$/m,
		'the sweep defaults to dry-run');
	unlike($text, qr/\|\|\s+"off"/, 'no off fallback remains');
	unlike($text, qr/users\/credhub-cleanup/, 'the old vault secret is not read');
	like($text, qr/params\.credhub_cleanup\.url/, 'the url override stays');
	like($text, qr/params\.credhub_cleanup\.ca_cert/, 'the ca_cert override stays');
};

subtest 'the off file turns cleanup off' => sub {
	my $text = slurp("$FindBin::Bin/../$off");
	like($text, qr/^\s*enabled:\s+false\s*$/m, 'enabled: false stands on its own line');
	unlike($text, qr/vault/, 'it reads nothing from vault');
};

# --- sweep parameter ---------------------------------------------------------

sub sweep_self {
	my ($sweep, @features) = @_;
	my $self = build_self(features => [@features ? @features : qw/ocfp valkey/]);
	$self->{env_obj}{lookups}{'params.credhub_cleanup.sweep'} = $sweep;
	return $self;
}

subtest 'sweep parameter' => sub {
	for my $ok ('off', 'dry-run', 'delete', 0, '') {
		reset_warnings();
		my $self = sweep_self($ok);
		eval { $self->validate_blacksmith_features };
		is($@, '', "validation accepts sweep '$ok'");
	}
	reset_warnings();
	my $self = sweep_self('dryrun');
	eval { $self->validate_blacksmith_features };
	like($@, qr/params\.credhub_cleanup\.sweep/, 'the message names the parameter');
	like($@, qr/'dryrun'/, 'the message shows the bad value');
	like($@, qr/off,\s+dry-run,\s+or\s+delete/, 'the message lists the accepted values');
};

subtest 'a bad sweep value is refused without the feature name' => sub {
	reset_warnings();
	my $self = sweep_self('dryrun', qw/external-bosh valkey/);
	eval { $self->validate_blacksmith_features };
	like($@, qr/params\.credhub_cleanup\.sweep/, 'validation refuses it');
};

subtest 'a bad sweep value is ignored when the wiring is not included' => sub {
	reset_warnings();
	for my $features ([qw/ocfp valkey skip-credhub-cleanup/], [qw/aws valkey/]) {
		my $self = sweep_self('dryrun', @$features);
		eval { $self->validate_blacksmith_features };
		is($@, '', "no error with @$features");
	}
};

done_testing;
