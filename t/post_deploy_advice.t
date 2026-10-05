#!/usr/bin/env perl
# Coverage for the next-steps advice printed after a deploy. Every
# "genesis do <env> <addon>" line must name an addon the kit ships, and the
# advice must not send operators to the bosh addon for tasks or VMs, because
# the broker API serves both. Needs the real genesis Perl library on
# GENESIS_LIB or ~/.genesis/lib.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/post-deploy.pm";

my $pkg   = 'Genesis::Hook::PostDeploy::Blacksmith';
my $hooks = "$FindBin::Bin/../hooks";
my @infos;

{
	package Stub::Env;
	sub get_call_path_with_env { 'genesis' . ' ' . 'my-env' }
}

{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*{"${pkg}::info"}         = sub { push @infos, sprintf(shift, @_) };
	*{"${pkg}::env"}          = sub { bless {}, 'Stub::Env' };
	*{"${pkg}::want_feature"} = sub { 1 };
}

my $self = bless {}, $pkg;
$self->display_next_steps;
my $text = join '', @infos;
$text =~ s/#[A-Za-z]+\{(.*?)\}/$1/g;

my @addons;
for my $line (split /\n/, $text) {
	push @addons, $1 while $line =~ /genesis my-env do (\w+)/g;
}
ok(scalar @addons, 'advice names at least one addon');
for my $addon (sort keys %{{ map { $_ => 1 } @addons }}) {
	my @files = glob("$hooks/addon-${addon}~*.pm");
	ok(scalar @files, "addon '$addon' has a hooks/addon-$addon~*.pm file");
}

like($text, qr{genesis my-env do -- curl /b/tasks}, 'tasks advice uses the broker API');
like($text, qr{genesis my-env do -- curl /b/blacksmith/vms}, 'VMs advice uses the broker API');
unlike($text, qr{genesis my-env do bosh}, 'no advice points at the bosh addon');
unlike($text, qr/internal BOSH director/i, 'no director access item remains');

done_testing;
