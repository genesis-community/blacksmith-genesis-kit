#!/usr/bin/env perl
# Coverage for the per-IaaS stemcell overlay in the blueprint hook. Under the
# ocfp feature the blueprint includes ocfp/<iaas>/stemcell.yml, straight after
# ocfp/<iaas>/ocf.yml, but only when the kit ships that file, which today is
# the pve one alone. The resolute feature stays the last stemcell file, so on a
# pve environment it still overrides the pin and the stemcell renders as
# ubuntu-resolute.
#
# Calls the hook's subs directly against a minimal mock $self, so it needs the
# real genesis Perl library on GENESIS_LIB or ~/.genesis/lib, the same as
# hooks/blueprint.pm itself, and spruce (or graft installed under that name)
# on PATH for the merge check.

use v5.20;
use warnings;
use FindBin;
use Test::More;
use File::Temp qw/tempdir/;
use JSON::PP;

require "$FindBin::Bin/../hooks/blueprint.pm";

my $kit_dir = "$FindBin::Bin/..";
my $dir     = tempdir(CLEANUP => 1);

# --- minimal mocks -----------------------------------------------------------

package MockEnv;
sub new    { my ($c, %a) = @_; bless {%a}, $c }
sub name   { 'lab' }
sub lookup { my ($s, $k, $d) = @_; return $s->{lookups}{$k} // $d }
sub path   { my ($s, $p) = @_; return "$s->{root}/env/$p" }
sub iaas   { $_[0]->{iaas} }
sub exodus_mount  { '/secret/exodus/' }
sub exodus_lookup { return $_[2] }

package MockKit;
sub new  { bless {dir => $_[1]}, $_[0] }
sub path { "$_[0]{dir}/$_[1]" }

package main;

{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*Genesis::Hook::Blueprint::Blacksmith::env = sub { $_[0]->{env_obj} };
	*Genesis::Hook::Blueprint::Blacksmith::kit = sub { $_[0]->{kit_obj} };
	for my $pkg (qw/Genesis::Hook::Blueprint Genesis::Hook::Blueprint::Blacksmith/) {
		*{"${pkg}::warning"} = sub { };
	}
}

# rendered_files - the files the blueprint lists for an ocfp environment on the
# given IaaS with the given extra features.
sub rendered_files {
	my ($iaas, @features) = @_;
	my $self = bless {
		env_obj  => MockEnv->new(root => $dir, iaas => $iaas),
		kit_obj  => MockKit->new($kit_dir),
		features => ['ocfp', @features],
		files    => [],
	}, 'Genesis::Hook::Blueprint::Blacksmith';
	$ENV{OCFP_IAAS} = $iaas;
	$self->validate_blacksmith_features;
	my ($iaas_count, $bosh, $forges) = $self->process_features;
	$self->apply_post_processing($iaas_count, $bosh);
	return @{ $self->{files} };
}

sub index_of {
	my ($file, @files) = @_;
	for my $i (0 .. $#files) { return $i if $files[$i] eq $file }
	return -1;
}

# stemcell_os - the params.stemcell_os the given files merge to, in order.
my $n = 0;
sub stemcell_os {
	my (@files) = @_;
	return 'no files' unless @files;
	my $out = qx(spruce merge @{[map { "$kit_dir/$_" } @files]} 2>/dev/null </dev/null | spruce json 2>&1);
	my $doc = eval { decode_json($out) } or return "unparsed: $out";
	return $doc->{params}{stemcell_os};
}

my $stemcell = 'ocfp/pve/stemcell.yml';

# --- pve ---------------------------------------------------------------------

my @pve = rendered_files('pve');
my $ocf = index_of('ocfp/pve/ocf.yml', @pve);
ok($ocf >= 0, 'a pve ocfp environment includes ocfp/pve/ocf.yml');
is(index_of($stemcell, @pve), $ocf + 1,
	'a pve ocfp environment includes the stemcell file right after ocf.yml');
is(scalar(grep { $_ eq $stemcell } @pve), 1, 'the stemcell file is included once');

# --- an IaaS without the file ------------------------------------------------

for my $iaas (qw/aws azure gcp vsphere stackit/) {
	my @files = rendered_files($iaas);
	ok(index_of("ocfp/$iaas/ocf.yml", @files) >= 0, "$iaas still includes its ocf.yml");
	is(scalar(grep { m{^ocfp/[^/]+/stemcell\.yml$} } @files), 0,
		"$iaas includes no stemcell file, since the kit has none for it");
}

# --- pve with the resolute feature -------------------------------------------

my @resolute = rendered_files('pve', 'resolute');
my $pin      = index_of($stemcell, @resolute);
my $res      = index_of('manifests/blacksmith/resolute.yml', @resolute);
ok($pin >= 0, 'pve with resolute still includes the stemcell file');
ok($res > $pin, 'the resolute manifest merges after the stemcell file');
my @after = grep { index_of($_, @resolute) > $pin && m{resolute} } @resolute;
my @before = grep { index_of($_, @resolute) < $pin && m{resolute} } @resolute;
is(scalar(@before), 0, 'no resolute manifest merges before the stemcell file');
ok(scalar(@after) > 0, 'the resolute manifests merge after the stemcell file');

# Merge just the stemcell files, in the order the blueprint lists them.
my @merge = grep { $_ eq $stemcell || m{^manifests/blacksmith/resolute\.yml$} } @resolute;
is(stemcell_os(@merge), 'ubuntu-resolute',
	'a pve environment with resolute renders ubuntu-resolute');
is(stemcell_os(grep { $_ eq $stemcell } @pve), 'ubuntu-noble',
	'a pve environment without resolute renders ubuntu-noble');

done_testing;
