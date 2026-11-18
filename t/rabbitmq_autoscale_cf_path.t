#!/usr/bin/env perl
# Coverage for the Cloud Foundry path in the rabbitmq-autoscale forge manifest.
# The CF deployment publishes its admin credentials, system domain, and agent
# certificates under the exodus mount, not under the secrets mount, so the
# meta.cf.exodus_path expression has to build its path from
# genesis.exodus_mount. The expression is taken from the manifest itself, so
# the test follows the file rather than a copy of it. The two mounts differ in
# the test environment so that reading the wrong one shows up.
#
# Needs spruce (or graft installed under that name) on PATH.

use v5.20;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

my $kit = "$FindBin::Bin/..";
my $dir = tempdir(CLEANUP => 1);

open my $fh, '<', "$kit/manifests/forges/rabbitmq-autoscale.yml"
	or die "rabbitmq-autoscale.yml: $!";
my ($expr) = map { /^\s+exodus_path:\s+(\(\(.*\)\))\s*$/ ? $1 : () } <$fh>;
close $fh;
ok(defined $expr, 'rabbitmq-autoscale.yml defines meta.cf.exodus_path');

my $file = "$dir/case.yml";
open my $out, '>', $file or die "$file: $!";
print $out <<"YAML";
genesis:
  env: test-env
  secrets_mount: /secret/
  exodus_mount: /secret/exodus/
meta:
  cf:
    exodus_path: $expr
YAML
close $out;

my $json = qx(spruce merge $file 2>&1 | spruce json 2>&1);
my $doc = eval { decode_json($json) };
ok($doc, 'the expression evaluates') or diag $json;
is($doc && $doc->{meta}{cf}{exodus_path}, '/secret/exodus/test-env/cf',
	'the CF path is built from the exodus mount');

done_testing;
