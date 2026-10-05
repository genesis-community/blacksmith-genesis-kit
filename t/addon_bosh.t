#!/usr/bin/env perl
# Coverage for the bosh addon: it must read the four connection keys the
# manifest exports from the environment's exodus data, print them as four
# shell-safe export lines on standard output, say on standard error that the
# output holds a secret, name the missing key when one is absent, and never
# run a command.
#
# Calls the hook's subs directly against a minimal mock $self, so it needs
# the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib, the same
# as hooks/addon-bosh~bo.pm itself.

use v5.20;
use warnings;
use FindBin;
use File::Temp ();
use Test::More;

require "$FindBin::Bin/../hooks/addon-bosh~bo.pm";

my $pkg = 'Genesis::Hook::Addon::Blacksmith::BOSH';

package MockEnv;
sub new  { my ($c, %a) = @_; bless {%a}, $c }
sub name { 'lab' }

package main;

my (@run_calls, @infos, $done);
{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*{"${pkg}::env"}         = sub { $_[0]->{env_obj} };
	*{"${pkg}::exodus_data"} = sub { my $s = shift; return $s->{exodus} unless @_; return $s->{exodus}{$_[0]} };
	*{"${pkg}::done"}        = sub { $done++; return 'done' };
	*{"${pkg}::info"}        = sub { push @infos, sprintf(shift, @_) };
	*{"${pkg}::run"}         = sub { push @run_calls, [@_]; die "addon must not run commands\n" };
}

my $pem = "-----BEGIN CERTIFICATE-----\nMIIB\nabc'def\n-----END CERTIFICATE-----\n";
my %good = (
	bosh_address  => 'https://10.0.0.6:25555',
	bosh_cacert   => $pem,
	bosh_username => 'admin',
	bosh_password => "it's a \$ecret `x` \"q\"",
);

sub mock { my (%ex) = @_; bless { env_obj => MockEnv->new, exodus => {%ex} }, $pkg }

sub capture {
	my ($self) = @_;
	my ($out, $err, $died) = ('', '', '');
	{
		local *STDOUT; local *STDERR;
		open(STDOUT, '>', \$out) or die; open(STDERR, '>', \$err) or die;
		eval { $self->perform; 1 } or $died = $@;
	}
	die $died if $died;
	return ($out, $err);
}

# --- prints four exports that survive eval -----------------------------------
{
	my ($out, $err) = capture(mock(%good));
	my @lines = grep { /^export / } split /\n/, $out;
	is(scalar(grep { /^export BOSH_(ENVIRONMENT|CA_CERT|CLIENT|CLIENT_SECRET)=/ } @lines), 4,
		'four BOSH_* export lines are printed');
	like($out, qr/^export BOSH_ENVIRONMENT='https:\/\/10\.0\.0\.6:25555'$/m, 'environment export');
	like($out, qr/^export BOSH_CLIENT='admin'$/m, 'client export');
	like($err, qr/secret/i, 'standard error warns the output holds a secret');
	like($err, qr/eval "\$\(genesis do lab bosh\)"/, 'standard error shows the eval usage');
	is($done, 1, 'addon finishes through done');

	for my $pair (['BOSH_CLIENT_SECRET', $good{bosh_password}], ['BOSH_CA_CERT', $pem], ['BOSH_CLIENT', 'admin'], ['BOSH_ENVIRONMENT', $good{bosh_address}]) {
		my ($var, $want) = @$pair;
		my ($fh, $file) = File::Temp::tempfile(UNLINK => 1);
		print $fh $out; close $fh;
		my $val = `bash -c 'eval "\$(cat $file)"; printf %s "\$$var"'`;
		is($val, $want, "$var survives eval in bash");
	}
}

# --- missing key -------------------------------------------------------------
{
	my %ex = %good; delete $ex{bosh_cacert};
	my $self = mock(%ex);
	my $died = eval { $self->get_blacksmith_bosh_info; 1 } ? '' : $@;
	like($died, qr/bosh_cacert/, 'bail names the missing key');
	like($died, qr{secret/exodus/lab/blacksmith}, 'bail names the exodus path');
	like($died, qr/deployed/, 'bail names the likely cause');
}

# --- no commands -------------------------------------------------------------
{
	@run_calls = ();
	capture(mock(%good));
	is(scalar @run_calls, 0, 'addon runs no commands');
}

done_testing;
