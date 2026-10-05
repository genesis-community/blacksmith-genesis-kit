#!/usr/bin/env perl
# Coverage for reading the deployment manifest in the pre-deploy hook. The
# hook loads GENESIS_MANIFEST_FILE with Genesis's own YAML loader, so ((var))
# placeholders must come back untouched, validate_cloud_config must report
# the instance group fields that are missing, and a file that is not YAML
# must produce an error naming the path, the loader's text, and the likely
# cause.
#
# Needs spruce (or graft installed under that name) on PATH, and the real
# genesis Perl library on GENESIS_LIB or ~/.genesis/lib.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/pre-deploy.pm";

my $pkg = 'Genesis::Hook::PreDeploy::Blacksmith';

my (@infos, @errors);
{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*{"${pkg}::info"}  = sub { push @infos,  sprintf(shift, @_) };
	*{"${pkg}::error"} = sub { push @errors, sprintf(shift, @_) };
	*{"${pkg}::run"}   = sub { die "pre-deploy manifest read must not call run directly\n" };
	*{"${pkg}::want_feature"} = sub { 0 };
	*{"${pkg}::env"}   = sub { undef };
}

my $self = bless {}, $pkg;
my $fixtures = "$FindBin::Bin/fixtures";

# Placeholders survive and nothing is interpolated.
{
	local $ENV{GENESIS_MANIFEST_FILE} = "$fixtures/manifest-unresolved.yml";
	my $m = $self->load_manifest;
	ok(ref $m eq 'HASH', 'load_manifest returns a hash') or diag explain $m;
	my $ig = $m->{instance_groups}[0];
	is($ig->{networks}[0]{static_ips}[0], '((blacksmith_ip))', 'ip placeholder left untouched');
	is($ig->{jobs}[0]{properties}{broker}{password}, '((broker_password))', 'password placeholder left untouched');

	@errors = (); @infos = ();
	ok(!$self->validate_cloud_config, 'validate_cloud_config fails when vm_type is missing');
	like(join('', @errors), qr/Instance group 'blacksmith' missing: vm_type\b/, 'missing vm_type reported');
}

# A file that is not YAML.
{
	local $ENV{GENESIS_MANIFEST_FILE} = "$fixtures/not-yaml.yml";
	@errors = ();
	my $m = $self->load_manifest;
	ok(!$m, 'load_manifest returns nothing for invalid YAML');
	my $text = join('', @errors);
	like($text, qr/\Q$fixtures\E\/not-yaml\.yml/, 'error names the manifest path');
	like($text, qr/valid YAML/i, 'error names the likely cause');

	@errors = ();
	ok(!$self->validate_cloud_config, 'validate_cloud_config fails on invalid YAML');
}

done_testing;
