#!/usr/bin/env perl
# Coverage for the SHIELD import in the pre-deploy hook. The hook must merge
# the import template through Genesis (spruce_merge), write the result to a
# private temporary file, hand that file to "shield import", and remove it
# afterwards. A failed merge must name the template and the merge error.
#
# run is stubbed, so no shield or bosh command is executed. Needs the real
# genesis Perl library on GENESIS_LIB or ~/.genesis/lib.

use v5.20;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use Test::More;

require "$FindBin::Bin/../hooks/pre-deploy.pm";

my $pkg      = 'Genesis::Hook::PreDeploy::Blacksmith';
my $template = "$FindBin::Bin/../manifests/templates/shield-backups-import.yml";
my $work     = tempdir(CLEANUP => 1);

my (@infos, @errors, @runs, @merges);
my ($merge_rc, $merge_err) = (0, '');
my ($file_mode, $file_body, $file_path);
my %params = (
	'meta.shield.admin_username' => 'admin',
	'meta.shield.admin_password' => 'adminpw',
	'meta.shield.address'        => 'https://shield.example',
	'params.shield_username'     => 'bs',
	'params.shield_password'     => 'bspw',
	'params.shield_tenant'       => 'blacksmith',
);

{
	package Stub::Env;
	sub partial_manifest_lookup { $params{$_[1]} }
	sub workpath { "$work/$_[1]" }
	package Stub::Kit;
	sub path { $template }
}

{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*{"${pkg}::info"}  = sub { push @infos,  sprintf(shift, @_) };
	*{"${pkg}::error"} = sub { push @errors, sprintf(shift, @_) };
	*{"${pkg}::env"}   = sub { bless {}, 'Stub::Env' };
	*{"${pkg}::kit"}   = sub { bless {}, 'Stub::Kit' };
	*{"${pkg}::spruce_merge"} = sub {
		my ($s, @args) = @_;
		push @merges, [@args];
		wantarray or die "spruce_merge must be called in list context\n";
		return ("imports: merged\n", $merge_rc, $merge_err);
	};
	*{"${pkg}::run"} = sub {
		my ($opts, $cmd, @args) = @_;
		push @runs, [$cmd, @args];
		if ($cmd =~ /^shield import/) {
			$file_path = $args[0];
			$file_mode = (stat $file_path)[2] & 07777 if -e $file_path;
			if (open my $fh, '<', $file_path) { local $/; $file_body = <$fh> }
		}
		return ('', 0);
	};
}

my $self = bless {}, $pkg;

# The merged document goes to a 0600 file that shield import reads.
{
	@runs = @merges = @errors = ();
	ok($self->setup_shield_integration, 'integration succeeds') or diag join '', @errors;
	is_deeply(\@merges, [[$template]], 'template merged through spruce_merge');
	my ($import) = grep { $_->[0] =~ /^shield import/ } @runs;
	ok($import, 'shield import ran');
	unlike($import->[0], qr/<\(/, 'no process substitution in the import command');
	like($import->[1], qr{^\Q$work\E/shield-import\.yml$}, 'import takes the temporary file');
	is(sprintf('%04o', $file_mode // 0), '0600', 'file was mode 0600 while the import ran');
	is($file_body, "imports: merged\n", 'file held the merged document');
	ok(!-e $file_path, 'file is gone afterwards');
}

# A failed merge names the template and the merge error, and imports nothing.
{
	@runs = @merges = @errors = ();
	($merge_rc, $merge_err) = (2, 'unresolved grab $BLACKSMITH_SHIELD_TENANT');
	ok(!$self->setup_shield_integration, 'integration fails when the merge fails');
	my $text = join '', @errors;
	like($text, qr/\Q$template\E/, 'error names the template');
	like($text, qr/unresolved grab/, 'error carries the merge error');
	ok(!(grep { $_->[0] =~ /^shield import/ } @runs), 'no import attempted');
	ok(!-e "$work/shield-import.yml", 'no temporary file left behind');
}

# The file is removed even when the import itself fails.
{
	($merge_rc, $merge_err) = (0, '');
	@runs = @errors = ();
	no strict 'refs';
	no warnings 'redefine';
	local *{"${pkg}::run"} = sub {
		my ($opts, $cmd, @args) = @_;
		if ($cmd =~ /^shield import/) { $file_path = $args[0]; return ('boom', 1) }
		return ('', 0);
	};
	ok(!$self->setup_shield_integration, 'integration fails when the import fails');
	ok(!-e $file_path, 'file is gone after a failed import');
}

done_testing;
