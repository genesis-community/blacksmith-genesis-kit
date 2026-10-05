#!/usr/bin/env perl
# Unit-level coverage for check_credhub_cleanup_client in
# Genesis::Hook::PostDeploy::Blacksmith. The check runs for an external
# director (external-bosh or ocfp) unless skip-credhub-cleanup is listed, the
# same decision the blueprint makes, and does nothing for an internal director
# or the skip feature. It reads the client ID and secret from the director's
# exodus record and never touches Blacksmith's vault. When the record lacks
# any of the five CredHub keys it repeats the blueprint's unwired warning,
# naming the missing keys, and makes no token request. Otherwise it warns
# (and returns false) when the director url or ca_cert is unusable, succeeds
# on an HTTP 200 from the UAA, warns with the status on any other answer, and
# passes the secret to curl on standard input instead of in its arguments.
#
# Calls the hook's sub directly against a minimal mock $self, so it needs
# the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib, the same
# as hooks/post-deploy.pm itself.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/post-deploy.pm";

my $pkg = 'Genesis::Hook::PostDeploy::Blacksmith';
my @keys = do { no warnings 'once'; @Genesis::Hook::Blueprint::Blacksmith::CREDHUB_EXODUS_KEYS };

# --- minimal mocks -----------------------------------------------------------

package MockVault;
sub AUTOLOAD { our $AUTOLOAD; die "the check must not read vault ($AUTOLOAD)\n" }
sub DESTROY {}

package MockEnv;
sub new    { my ($c, %a) = @_; bless {%a, slugs => []}, $c }
sub name   { 'lab' }
sub lookup { my ($s, $k, $d) = @_; return $s->{lookups}{$k} // $d }
sub exodus_mount { '/secret/exodus/' }
sub secrets_base { 'secret/lab/blacksmith/' }
sub get_call_path_with_env { 'genesis lab' }
sub vault { MockVault->new }
sub exodus_lookup {
	my ($s, $key, $default, $slug) = @_;
	push @{$s->{slugs}}, $slug;
	my $v = $s->{exodus}{$key};
	return defined($v) ? $v : $default;
}

package main;

my (@run_calls, @infos, @warnings, $run_result);

{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*{"${pkg}::env"} = sub { $_[0]->{env_obj} };
	*{"${pkg}::want_feature"} = sub { scalar grep { $_ eq $_[1] } @{$_[0]->{features}} };
	*{"${pkg}::info"}    = sub { push @infos, sprintf(shift, @_) };
	*{"${pkg}::warning"} = sub { push @warnings, sprintf(shift, @_) };
	*{"${pkg}::run"}     = sub { push @run_calls, [@_]; return @$run_result };
}

my $FAKE_SECRET = 'fake-secret-for-tests-only';

sub full_exodus {
	return (
		url                              => 'https://10.0.0.6:25555',
		ca_cert                          => "-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----\n",
		credhub_url                      => 'https://10.0.0.6:8844',
		blacksmith_credhub_client_id     => 'blacksmith_credhub',
		blacksmith_credhub_client_secret => $FAKE_SECRET,
		blacksmith_credhub_ca_cert       => "-----BEGIN CERTIFICATE-----\ny\n-----END CERTIFICATE-----\n",
		blacksmith_credhub_director_name => 'lab-bosh',
	);
}

sub build_self {
	my (%o) = @_;
	my %exodus = $o{exodus} ? %{$o{exodus}} : full_exodus();
	delete @exodus{ @{$o{without} // []} };
	my $env = MockEnv->new(lookups => $o{lookups} // {}, exodus => \%exodus);
	return bless { env_obj => $env, features => $o{features} // ['external-bosh'] }, $pkg;
}

sub reset_state { @run_calls = @infos = @warnings = (); $run_result = ['200', 0] }

subtest 'the exodus keys are the five the blueprint holds' => sub {
	is(scalar(@keys), 5, 'five keys');
	ok((grep { $_ eq 'blacksmith_credhub_client_id' } @keys), 'the client ID key is among them');
	ok((grep { $_ eq 'blacksmith_credhub_client_secret' } @keys), 'the client secret key is among them');
};

subtest 'an internal director does nothing' => sub {
	reset_state();
	my $self = build_self(features => []);
	ok($self->check_credhub_cleanup_client, 'returns true');
	is(scalar(@run_calls), 0, 'curl is not run');
	is(scalar(@warnings) + scalar(@infos), 0, 'nothing is printed');
};

subtest 'skip-credhub-cleanup does nothing, even with the keys missing' => sub {
	for my $features (['external-bosh', 'skip-credhub-cleanup'], ['ocfp', 'skip-credhub-cleanup']) {
		reset_state();
		my $self = build_self(features => $features, without => [@keys]);
		ok($self->check_credhub_cleanup_client, "$features->[0] returns true");
		is(scalar(@run_calls), 0, 'curl is not run');
		is(scalar(@warnings) + scalar(@infos), 0, 'nothing is printed');
	}
};

subtest 'the deprecated credhub-cleanup name does not gate the check' => sub {
	reset_state();
	my $self = build_self(features => ['credhub-cleanup']);
	ok($self->check_credhub_cleanup_client, 'an internal director with the old name returns true');
	is(scalar(@run_calls), 0, 'curl is not run');
};

subtest 'ocfp runs the check without naming a feature' => sub {
	reset_state();
	my $self = build_self(features => ['ocfp']);
	ok($self->check_credhub_cleanup_client, 'returns true');
	is(scalar(@run_calls), 1, 'curl is run once');
};

subtest 'status 200 succeeds with the credentials from the exodus record' => sub {
	reset_state();
	my $self = build_self();
	ok($self->check_credhub_cleanup_client, 'returns true');
	is(scalar(@warnings), 0, 'no warning');
	like($infos[-1], qr/blacksmith_credhub can authenticate/, 'success is reported');
	my ($opts, $cmd, @args) = @{ $run_calls[0] };
	is($opts->{stdin}, qq{user = "blacksmith_credhub:$FAKE_SECRET"\n}, 'the exodus client ID and secret go to curl on stdin');
	is($args[-1], 'https://10.0.0.6:8443/oauth/token', 'the UAA is the director host on 8443');
	my %slugs = map { $_ => 1 } @{ $self->env->{slugs} };
	is_deeply([sort keys %slugs], ['lab/bosh'], 'every exodus read is from the bosh record');
};

subtest 'an exodus client ID other than the default is used' => sub {
	reset_state();
	my $self = build_self(exodus => { full_exodus(), blacksmith_credhub_client_id => 'fake_other_client' });
	ok($self->check_credhub_cleanup_client, 'returns true');
	is($run_calls[0][0]{stdin}, qq{user = "fake_other_client:$FAKE_SECRET"\n}, 'the exodus ID is sent');
};

subtest 'params.credhub_cleanup.client_id overrides the ID the way the wiring does' => sub {
	reset_state();
	my $self = build_self(lookups => { 'params.credhub_cleanup.client_id' => 'fake_override_client' });
	ok($self->check_credhub_cleanup_client, 'returns true');
	is($run_calls[0][0]{stdin}, qq{user = "fake_override_client:$FAKE_SECRET"\n}, 'the override ID is sent with the exodus secret');
};

subtest 'the secret reaches no process argument and no output' => sub {
	reset_state();
	$run_result = ['401', 0];
	my $self = build_self();
	$self->check_credhub_cleanup_client;
	for my $call (@run_calls) {
		my ($opts, @argv) = @$call;
		unlike(join("\0", map { $_ // '' } @argv), qr/\Q$FAKE_SECRET\E/, 'the secret is not in the command or its arguments');
		like($opts->{stdin}, qr/\Q$FAKE_SECRET\E/, 'the secret is on stdin');
	}
	unlike(join('', @warnings, @infos), qr/\Q$FAKE_SECRET\E/, 'the secret is never printed');
};

subtest 'a 401 warns with the status and advises a director redeploy' => sub {
	reset_state();
	$run_result = ['401', 0];
	my $self = build_self();
	ok(!$self->check_credhub_cleanup_client, 'returns false');
	like($warnings[0], qr/status 401/, 'the warning carries the status');
	like(join('', @warnings), qr/Likely cause.*Repair/s, 'the warning gives a likely cause and a repair');
	like(join('', @warnings), qr/Repair: redeploy the director with the current BOSH kit release/, 'the repair is a director redeploy');
	unlike(join('', @warnings), qr/kit manual|users\/credhub-cleanup|vault/, 'no hand procedure or vault path is named');
	unlike(join('', @warnings, @infos), qr/\Q$FAKE_SECRET\E/, 'the secret is never printed');
};

subtest 'a curl failure warns with its exit code' => sub {
	reset_state();
	$run_result = ['', 60];
	my $self = build_self();
	ok(!$self->check_credhub_cleanup_client, 'returns false');
	like($warnings[0], qr/none, curl exit 60/, 'the warning carries the curl exit code');
};

subtest 'any missing exodus key repeats the unwired warning without calling curl' => sub {
	for my $key (@keys) {
		reset_state();
		my $self = build_self(without => [$key]);
		ok(!$self->check_credhub_cleanup_client, "$key missing returns false");
		is(scalar(@run_calls), 0, "$key missing does not run curl");
		is(scalar(@warnings), 1, "$key missing warns once");
		like($warnings[0], qr/\Q$key\E/, "the warning names $key");
		like($warnings[0], qr/unconfigured/, 'the warning says cleanup is unconfigured');
		like($warnings[0], qr/skip-credhub-cleanup/, 'the warning names the skip feature');
		my @others = grep { $_ ne $key } @keys;
		unlike($warnings[0], qr/\Q$_\E/, "the warning does not name present key $_") for @others;
		unlike($warnings[0], qr/\Q$FAKE_SECRET\E/, 'the warning does not print the secret');
	}
};

subtest 'several missing keys are all named' => sub {
	reset_state();
	my $self = build_self(without => [@keys[1, 2]]);
	ok(!$self->check_credhub_cleanup_client, 'returns false');
	like($warnings[0], qr/\Q$keys[1]\E/, 'the first missing key is named');
	like($warnings[0], qr/\Q$keys[2]\E/, 'the second missing key is named');
	is(scalar(@run_calls), 0, 'curl is not run');
};

subtest 'an empty secret in the exodus record counts as missing' => sub {
	reset_state();
	my $self = build_self(exodus => { full_exodus(), blacksmith_credhub_client_secret => '' });
	ok(!$self->check_credhub_cleanup_client, 'returns false');
	like($warnings[0], qr/blacksmith_credhub_client_secret/, 'the secret key is named');
	is(scalar(@run_calls), 0, 'curl is not run');
};

subtest 'an unusable director url or ca_cert warns without calling curl' => sub {
	for my $case (
		['no exodus url',     build_self(without => ['url'])],
		['no exodus ca_cert', build_self(without => ['ca_cert'])],
		['http url',          build_self(exodus => { full_exodus(), url => 'http://10.0.0.6:25555' })],
	) {
		my ($label, $self) = @$case;
		reset_state();
		ok(!$self->check_credhub_cleanup_client, "$label returns false");
		is(scalar(@run_calls), 0, "$label does not run curl");
		like($warnings[0], qr/Could not check the blacksmith_credhub UAA client/, "$label warns");
	}
};

done_testing;
