#!/usr/bin/env perl
# Coverage for the boss addon: the environment it exports must use the
# BLACKSMITH_* names the boss CLI reads for its URL and credentials.
#
# Calls the hook's subs directly against a minimal mock $self, so it needs
# the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib, the same
# as hooks/addon-boss~b.pm itself.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/addon-boss~b.pm";

my $pkg = 'Genesis::Hook::Addon::Blacksmith::Boss';

my %seen;
{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*{"${pkg}::env"}                            = sub { undef };
	*{"${pkg}::info"}                           = sub { };
	*{"${pkg}::error"}                          = sub { };
	*{"${pkg}::done"}                           = sub { 'done' };
	*{"${pkg}::get_blacksmith_connection_info"} = sub {
		return { url => 'https://broker.example', username => 'USER', password => 'PASS' };
	};
	*{"${pkg}::check_command_availability"}     = sub { 1 };
	*{"${pkg}::run"} = sub {
		$seen{$_} = $ENV{$_} for grep { /^(?:BOSS|BLACKSMITH)_/ } keys %ENV;
		return ('', 0, '');
	};
}

delete @ENV{grep { /^(?:BOSS|BLACKSMITH)_/ } keys %ENV};
bless({ args => ['catalog'] }, $pkg)->perform;

is($seen{BLACKSMITH_URL},      'https://broker.example', 'exports BLACKSMITH_URL');
is($seen{BLACKSMITH_USERNAME}, 'USER',                   'exports BLACKSMITH_USERNAME');
is($seen{BLACKSMITH_PASSWORD}, 'PASS',                   'exports BLACKSMITH_PASSWORD');
ok(!exists $seen{BOSS_URL} && !exists $seen{BOSS_USERNAME} && !exists $seen{BOSS_PASSWORD},
	'does not export the BOSS_* names boss ignores');

done_testing;
