#!/usr/bin/env perl
# Coverage for the register addon's Cloud Foundry environment name. With no
# argument, the CF environment is the blacksmith environment's own name, which
# is how OCFP pairs the two (they share a name and differ by kit type in the
# exodus path). With an argument, the argument names the CF environment and
# reaches the CA sync and the CF lookup. The old blacksmith-<x> to cf-<x>
# inference is gone.
#
# Calls the hook's subs directly against a minimal mock $self, so it needs
# the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib, the same
# as hooks/addon-register~re.pm itself.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/addon-register~re.pm";

my $pkg = 'Genesis::Hook::Addon::Blacksmith::Register';

package MockEnv;
sub new  { my ($c, %a) = @_; bless {%a}, $c }
sub name { $_[0]->{name} }

package main;

my (@ca_sync_args, @cf_info_args, $done);
{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*{"${pkg}::env"}                       = sub { $_[0]->{env_obj} };
	*{"${pkg}::info"}                      = sub { };
	*{"${pkg}::warning"}                   = sub { };
	*{"${pkg}::error"}                     = sub { };
	*{"${pkg}::done"}                      = sub { $done++; return 'done' };
	*{"${pkg}::check_command_availability"} = sub { 1 };
	*{"${pkg}::get_blacksmith_connection_info"} = sub { {} };
	*{"${pkg}::ca_sync"}                   = sub { push @ca_sync_args, $_[1]; 1 };
	*{"${pkg}::_get_cf_info"}              = sub { push @cf_info_args, $_[1]; { api => 'https://api.example' } };
	*{"${pkg}::_connect_to_cf"}            = sub { 1 };
	*{"${pkg}::_register_service_broker"}  = sub { 1 };
	*{"${pkg}::_enable_service_access"}    = sub { 1 };
}

sub self_for {
	my (%a) = @_;
	return bless {
		env_obj => MockEnv->new(name => $a{env}),
		args    => $a{args} // [],
	}, $pkg;
}

# Default: no argument names the blacksmith environment itself, with no cf- inference.
{
	my $self = self_for(env => 'blacksmith-dev');
	is($self->_determine_cf_environment, 'blacksmith-dev',
		'no argument: the CF environment is the environment name, not cf-<x>');
}

{
	my $self = self_for(env => 'lab');
	is($self->_determine_cf_environment, 'lab',
		'no argument on a plain name: the CF environment is the environment name');
}

# Explicit argument: it names the CF environment.
{
	my $self = self_for(env => 'blacksmith-dev', args => ['cf-dev']);
	is($self->_determine_cf_environment, 'cf-dev',
		'an argument names the CF environment');
}

# perform hands the chosen name to the CA sync and the CF lookup.
{
	@ca_sync_args = @cf_info_args = ();
	my $self = self_for(env => 'lab');
	$self->perform;
	is_deeply(\@ca_sync_args, ['lab'], 'perform: default syncs CA for the environment name');
	is_deeply(\@cf_info_args, ['lab'], 'perform: default looks up the environment name');
}

{
	@ca_sync_args = @cf_info_args = ();
	my $self = self_for(env => 'blacksmith-dev', args => ['cf-dev']);
	$self->perform;
	is_deeply(\@ca_sync_args, ['cf-dev'], 'perform: argument syncs CA for the named CF environment');
	is_deeply(\@cf_info_args, ['cf-dev'], 'perform: argument looks up the named CF environment');
}

done_testing;
