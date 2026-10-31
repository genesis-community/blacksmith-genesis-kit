#!/usr/bin/env perl
# Coverage for the blacksmith_services_ca synchronization the post-deploy
# hook runs. A failed sync must fail the deploy through bail, and the message
# must carry the child's real error (from stderr or stdout) and the command
# that retries the sync. A successful sync must not bail. Needs the real
# genesis Perl library on GENESIS_LIB or ~/.genesis/lib.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/post-deploy.pm";

my $pkg = 'Genesis::Hook::PostDeploy::Blacksmith';

package MockVault; sub has { 1 }
package MockEnv;
sub name { 'lab' }
sub secrets_base { 'secret/lab/blacksmith/' }
sub vault { bless {}, 'MockVault' }
sub get_call_path_with_env { 'genesis lab' }
package main;

my ($run_result, @errors);
{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*{"${pkg}::env"}      = sub { bless {}, 'MockEnv' };
	*{"${pkg}::info"}     = sub { };
	*{"${pkg}::warning"}  = sub { };
	*{"${pkg}::error"}    = sub { push @errors, sprintf(shift, @_) };
	*{"${pkg}::bail"}     = sub { die sprintf(shift, @_) . "\n" };
	*{"${pkg}::run"}      = sub { @$run_result };
	*{"${pkg}::want_feature"} = sub { $_[1] eq 'broker-tls' };
}

sub attempt {
	@errors = ();
	my $self = bless {}, $pkg;
	my $ok = eval { $self->sync_blacksmith_services_ca; 1 };
	return ($ok, $@);
}

# child reports on stderr
$run_result = ['', 1, 'Missing jq'];
my ($ok, $err) = attempt();
ok(!$ok, 'a failed sync fails the deploy');
like($err, qr/Missing jq/, 'message carries the child stderr');
like($err, qr/genesis lab do register/, 'message names the retry command');

# child reports on stdout only
$run_result = ["FATAL: vault is sealed\n", 1, ''];
($ok, $err) = attempt();
ok(!$ok, 'a failed sync with stdout-only output fails the deploy');
like($err, qr/vault is sealed/, 'message carries the child stdout');

# child prints nothing at all
$run_result = ['', 3, ''];
($ok, $err) = attempt();
ok(!$ok, 'a silent failure still fails the deploy');
like($err, qr/status 3/, 'message names the exit status');

# success
$run_result = ['', 0, ''];
($ok, $err) = attempt();
ok($ok, 'a successful sync does not fail the deploy') or diag $err;
is(scalar @errors, 0, 'a successful sync reports no errors');

done_testing;
