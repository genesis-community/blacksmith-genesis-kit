package Genesis::Hook::Addon::Blacksmith::Boss v1.2.0;

use v5.20;
use warnings;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . '/.genesis/lib' }

use parent qw(Genesis::Hook::Addon);

use Genesis qw/bail info warning error run/;

# Include common methods from mixin
BEGIN {
	require File::Basename;
	my $mixin_file = File::Basename::dirname(__FILE__) . '/_addon.pm';
	do $mixin_file or die "Failed to include addon mixin $mixin_file: $!";
}

sub cmd_details {
	return
		"Interacts with the Blacksmith broker via the 'boss' CLI.\n".
		"The boss CLI must be installed separately.\n".
		"See https://github.com/blacksmith-community/boss for details.";
}

sub perform {
	my ($self) = @_;
	my $env = $self->env;

	# Check if boss is installed using mixin method
	my $install_hints = [
		{ os => 'All', cmd => 'Download from https://github.com/blacksmith-community/boss/releases' }
	];
	
	unless ($self->check_command_availability('boss', $install_hints)) {
		info("\n");
		info("The 'boss' CLI is the Blacksmith OSB Service Broker client.\n");
		info("It provides a command-line interface for managing service instances.\n");
		info("\n");
		info("For installation instructions, visit:\n");
		info("  #B{https://github.com/blacksmith-community/boss}\n");
		return $self->done(0);
	}

	# Get connection details using mixin method
	my $connection_info = $self->get_blacksmith_connection_info();
	
	# Set environment variables for boss
	$ENV{BOSS_URL} = $connection_info->{url};
	$ENV{BOSS_USERNAME} = $connection_info->{username};
	$ENV{BOSS_PASSWORD} = $connection_info->{password};
	
	info("Connecting to Blacksmith at #C{%s}...\n", $connection_info->{url});
	
	# Execute boss with all provided arguments
	my ($out, $rc, $err) = run({interactive => 1}, 'boss "$@"', @{$self->{args}});
	
	if ($rc != 0) {
		error("\nBoss command failed: %s\n", $err || 'Unknown error');
		return $self->done(0);
	}

	return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1: