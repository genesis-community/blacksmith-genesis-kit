#!/usr/bin/env perl
# Coverage for the curl addon: the command it hands to run must pass curl the
# basic-auth pair and the full URL exactly once, followed only by the caller's
# extra curl options. The captured command is executed for real under /bin/sh
# against a stub curl that prints each argument on its own line.
#
# Calls the hook's subs directly against a minimal mock $self, so it needs
# the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib, the same
# as hooks/addon-curl~cu.pm itself.

use v5.20;
use warnings;
use FindBin;
use File::Temp ();
use Test::More;

require "$FindBin::Bin/../hooks/addon-curl~cu.pm";

my $pkg = 'Genesis::Hook::Addon::Blacksmith::Curl';

package MockEnv;
sub new  { my ($c, %a) = @_; bless {%a}, $c }
sub name { 'lab' }

package main;

my (@run_calls, $done);
{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*{"${pkg}::env"}                          = sub { $_[0]->{env_obj} };
	*{"${pkg}::info"}                         = sub { };
	*{"${pkg}::error"}                        = sub { };
	*{"${pkg}::done"}                         = sub { $done++; return 'done' };
	*{"${pkg}::get_blacksmith_connection_info"} = sub {
		return { url => 'https://broker.example', username => 'USER', password => 'PASS' };
	};
	*{"${pkg}::check_command_availability"}   = sub { 1 };
	*{"${pkg}::validate_required_args"}       = sub { 1 };
	*{"${pkg}::run"}                          = sub { push @run_calls, [@_]; return ('', 0, '') };
}

my $bin = File::Temp->newdir;
my $stub = "$bin/curl";
open my $fh, '>', $stub or die "cannot write stub: $!";
print $fh "#!/bin/sh\nfor a in \"\$@\"; do printf '%s\\n' \"\$a\"; done\n";
close $fh;
chmod 0755, $stub;

sub argv_for {
	my (@args) = @_;
	@run_calls = ();
	my $self = bless { env_obj => MockEnv->new, args => [@args] }, $pkg;
	$self->perform;
	my ($opts, $cmd, @cargs) = @{ $run_calls[0] };
	local $ENV{PATH} = "$bin";
	open my $ph, '-|', '/bin/sh', '-c', $cmd, 'sh', @cargs or die "cannot run: $!";
	my @out = map { chomp; $_ } <$ph>;
	close $ph;
	return ($opts, @out);
}

{
	my ($opts, @argv) = argv_for('b/status', '-X', 'POST');
	is($run_calls[0][0]{interactive}, 1, 'run is interactive');
	is_deeply(\@argv, ['-u', 'USER:PASS', 'https://broker.example/b/status', '-X', 'POST'],
		'curl gets auth, URL, then only the extra options');
}

{
	my ($opts, @argv) = argv_for('b/status');
	is_deeply(\@argv, ['-u', 'USER:PASS', 'https://broker.example/b/status'],
		'with no extras curl gets only auth and URL');
}

done_testing;
