#!/usr/bin/env perl
# Coverage for the forge pieces of the cloud-config hook. The hook builds a
# network for each forge feature that is on (valkey-service, redis-service,
# rabbitmq-service), and two forge vm_types, default and small. The test
# stubs the Genesis helpers the hook calls, runs perform, and inspects the
# cloud config it hands to build_cloud_config.
#
# Needs the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/cloud-config.pm";

my $pkg = 'Genesis::Hook::CloudConfig::Blacksmith';

my (%features, %lookups, @network_calls, $built);
{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*{"${pkg}::completed"}     = sub { 0 };
	*{"${pkg}::done"}          = sub { 1 };
	*{"${pkg}::want_feature"}  = sub { $features{$_[1]} ? 1 : 0 };
	*{"${pkg}::cpi_enabled"}   = sub { 0 };
	*{"${pkg}::az_cloud_properties"}       = sub { {} };
	*{"${pkg}::network_reference"}         = sub { 'net-ref' };
	*{"${pkg}::subnet_reference"}          = sub { 'subnet-ref' };
	*{"${pkg}::get_network_security_groups"} = sub { ['default'] };
	*{"${pkg}::TRUE"}          = sub { 1 };
	*{"${pkg}::for_scale"}     = sub { $_[2] };
	*{"${pkg}::_cloud_properties_for_iaas"} = sub { my ($s, %p) = @_; $p{pve} };
	*{"${pkg}::vm_type_definition"}   = sub { +{ name => $_[1] } };
	*{"${pkg}::disk_type_definition"} = sub { +{ name => $_[1] } };
	*{"${pkg}::network_definition"}   = sub {
		my ($s, $name, %args) = @_;
		push @network_calls, { name => $name, %args };
		return +{ name => $name, subnets => [{ az => 'env-z2' }] };
	};
	*{"${pkg}::build_cloud_config"}   = sub { $built = $_[1]; $built };
	*{"${pkg}::env"}          = sub {
		bless {}, 'Stub::Env';
	};
	*{"Stub::Env::iaas"}  = sub { 'pve' };
	*{"Stub::Env::name"}  = sub { 'test-env' };
	*{"Stub::Env::lookup"} = sub {
		my ($s, $key, $default) = @_;
		return exists $lookups{$key} ? $lookups{$key} : $default;
	};
	*{"Stub::Env::ocfp_config_lookup"} = sub { $_[2] };
}

sub run_hook {
	my (%f) = @_;
	%features = %f; @network_calls = (); $built = undef;
	my $self = bless {}, $pkg;
	$self->perform;
	return $built;
}

sub by_name { my ($list, $name) = @_; (grep { $_->{name} eq $name } @$list)[0] }

# Only valkey: the cloud config is what it was before the other forges.
{
	my $cc = run_hook(valkey => 1);
	is_deeply([map { $_->{name} } @{$cc->{networks}}], ['blacksmith', 'valkey-service'],
		'valkey alone generates only the valkey-service forge network');
	is_deeply([map { $_->{name} } @network_calls], ['blacksmith', 'valkey-service'],
		'network_definition is called for blacksmith and valkey-service only');
	my $call = $network_calls[1];
	is($call->{strategy}, 'ocfp', 'valkey-service uses the ocfp strategy');
	is($call->{name_prefix}, '', 'valkey-service has an empty name prefix');
	is_deeply($call->{dynamic_subnets}{subnets}, ['ocfp-1'], 'valkey-service reads subnet ocfp-1');
	is_deeply($call->{dynamic_subnets}{allocation}, { size => 0, statics => 0 }, 'valkey-service allocates nothing dynamically');
	is($cc->{networks}[1]{subnets}[0]{az}, 'z1', 'valkey-service subnet az is the bare z1');
	is_deeply([map { $_->{name} } @{$cc->{azs}}], ['z1'], 'the bare z1 az is defined');
}

# No forge features at all: no forge networks, no z1.
{
	my $cc = run_hook();
	is_deeply([map { $_->{name} } @{$cc->{networks}}], ['blacksmith'], 'no forge feature, no forge network');
	is_deeply($cc->{azs}, [], 'no forge feature, no z1 az');
}

# Redis and RabbitMQ get the same network as valkey.
{
	my $cc = run_hook(valkey => 1, redis => 1, rabbitmq => 1);
	is_deeply([map { $_->{name} } @{$cc->{networks}}],
		['blacksmith', 'valkey-service', 'redis-service', 'rabbitmq-service'],
		'each enabled forge generates its own service network');
	my ($valkey, $redis, $rabbit) = @network_calls[1 .. 3];
	for my $c ($redis, $rabbit) {
		is($c->{strategy}, 'ocfp', "$c->{name} uses the ocfp strategy");
		is($c->{name_prefix}, '', "$c->{name} has an empty name prefix");
		is_deeply($c->{dynamic_subnets}{subnets}, ['ocfp-1'], "$c->{name} reads subnet ocfp-1");
		is_deeply($c->{dynamic_subnets}{allocation}, { size => 0, statics => 0 }, "$c->{name} allocates nothing dynamically");
		is_deeply($c->{dynamic_subnets}{cloud_properties_for_iaas}, $valkey->{dynamic_subnets}{cloud_properties_for_iaas},
			"$c->{name} carries the same cloud properties as valkey-service");
		is(by_name($cc->{networks}, $c->{name})->{subnets}[0]{az}, 'z1', "$c->{name} subnet az is the bare z1");
	}
}

# Redis alone and RabbitMQ alone.
{
	my $cc = run_hook(redis => 1);
	is_deeply([map { $_->{name} } @{$cc->{networks}}], ['blacksmith', 'redis-service'], 'redis alone');
	is_deeply([map { $_->{name} } @{$cc->{azs}}], ['z1'], 'redis alone defines the z1 az its network uses');
	$cc = run_hook(rabbitmq => 1);
	is_deeply([map { $_->{name} } @{$cc->{networks}}], ['blacksmith', 'rabbitmq-service'], 'rabbitmq alone');
	is_deeply([map { $_->{name} } @{$cc->{azs}}], ['z1'], 'rabbitmq alone defines the z1 az its network uses');
}

done_testing;
