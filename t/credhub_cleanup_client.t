#!/usr/bin/env perl
# Unit-level coverage for check_credhub_cleanup_client in
# Genesis::Hook::PostDeploy::Blacksmith: the check must do nothing unless the
# credhub-cleanup feature is on, must warn (and return false) when the bosh
# exodus record or the vault secret is unusable, must succeed on an HTTP 200
# from the UAA, must warn with the status on any other answer, and must pass
# the secret to curl on standard input instead of in its arguments.
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

# --- minimal mocks -----------------------------------------------------------

package MockVault;
sub new { my ($c, %a) = @_; bless {%a}, $c }
sub get { my ($s) = @_; die "vault unavailable\n" if $s->{die}; return $s->{secret} }

package MockEnv;
sub new    { my ($c, %a) = @_; bless {%a}, $c }
sub name   { 'lab' }
sub lookup { my ($s, $k, $d) = @_; return $s->{lookups}{$k} // $d }
sub exodus_mount { '/secret/exodus/' }
sub secrets_base { 'secret/lab/blacksmith/' }
sub get_call_path_with_env { 'genesis lab' }
sub vault { $_[0]->{vault} }
sub exodus_lookup { my ($s, $key) = @_; return $s->{exodus}{$key} }

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

sub build_self {
	my (%o) = @_;
	my $env = MockEnv->new(
		lookups => {},
		exodus  => exists $o{exodus} ? $o{exodus}
			: { url => 'https://10.0.0.6:25555', ca_cert => "-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----\n" },
		vault   => MockVault->new(secret => $o{secret} // 's3cret', die => $o{vault_dies}),
	);
	return bless { env_obj => $env, features => $o{features} // ['credhub-cleanup'] }, $pkg;
}

sub reset_state { @run_calls = @infos = @warnings = (); $run_result = ['200', 0] }

subtest 'feature off does nothing' => sub {
	reset_state();
	my $self = build_self(features => []);
	ok($self->check_credhub_cleanup_client, 'returns true');
	is(scalar(@run_calls), 0, 'curl is not run');
	is(scalar(@warnings) + scalar(@infos), 0, 'nothing is printed');
};

subtest 'status 200 succeeds' => sub {
	reset_state();
	my $self = build_self();
	ok($self->check_credhub_cleanup_client, 'returns true');
	is(scalar(@warnings), 0, 'no warning');
	like($infos[-1], qr/blacksmith_credhub can authenticate/, 'success is reported');
	my ($opts, $cmd, @args) = @{ $run_calls[0] };
	is($opts->{stdin}, qq{user = "blacksmith_credhub:s3cret"\n}, 'the credentials go to curl on stdin');
	unlike(join(' ', $cmd, @args), qr/s3cret/, 'the secret is not in the command or its arguments');
	is($args[-1], 'https://10.0.0.6:8443/oauth/token', 'the UAA is the director host on 8443');
};

subtest 'a 401 warns with the status' => sub {
	reset_state();
	$run_result = ['401', 0];
	my $self = build_self();
	ok(!$self->check_credhub_cleanup_client, 'returns false');
	like($warnings[0], qr/status 401/, 'the warning carries the status');
	like(join('', @warnings), qr/Likely cause.*Repair/s, 'the warning gives a likely cause and a repair');
	unlike(join('', @warnings, @infos), qr/s3cret/, 'the secret is never printed');
};

subtest 'a curl failure warns with its exit code' => sub {
	reset_state();
	$run_result = ['', 60];
	my $self = build_self();
	ok(!$self->check_credhub_cleanup_client, 'returns false');
	like($warnings[0], qr/none, curl exit 60/, 'the warning carries the curl exit code');
};

subtest 'an unusable exodus record or secret warns without calling curl' => sub {
	for my $case (
		['no exodus url',     build_self(exodus => { ca_cert => 'x' })],
		['no exodus ca_cert', build_self(exodus => { url => 'https://10.0.0.6:25555' })],
		['http url',          build_self(exodus => { url => 'http://10.0.0.6:25555', ca_cert => 'x' })],
		['empty secret',      build_self(secret => '')],
		['vault dies',        build_self(vault_dies => 1)],
	) {
		my ($label, $self) = @$case;
		reset_state();
		ok(!$self->check_credhub_cleanup_client, "$label returns false");
		is(scalar(@run_calls), 0, "$label does not run curl");
		like($warnings[0], qr/Could not check the blacksmith_credhub UAA client/, "$label warns");
	}
};

done_testing;
