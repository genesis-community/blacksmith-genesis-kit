package Genesis::Hook::Addon::Blacksmith::Curl v1.0.4;

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
		"Issues raw HTTP requests (via curl) against the Blacksmith Broker.\n".
		"Authentication is handled automatically.\n".
		"Usage: curl <path> [curl options...]\n".
		"Example: curl /v2/catalog -v";
}

sub perform {
	my ($self) = @_;
	my $env = $self->env;

	# Validate curl is available using mixin method
	my $install_hints = [
		{ os => 'macOS',  cmd => 'brew install curl' },
		{ os => 'Ubuntu', cmd => 'apt-get install curl' },
		{ os => 'CentOS', cmd => 'yum install curl' }
	];
	
	unless ($self->check_command_availability('curl', $install_hints)) {
		return $self->done(0);
	}

	# Validate arguments using mixin method
	my $usage_msg = sprintf(
		"  #G{genesis do %s -- curl <path> [curl options...]}\n\n".
		"#Bu{Examples:}\n".
		"  # Get service catalog:\n".
		"  #G{genesis do %s -- curl /v2/catalog}\n\n".
		"  # Get service instances with verbose output:\n".
		"  #G{genesis do %s -- curl /v2/service_instances -v}\n\n".
		"  # Make a POST request:\n".
		"  #G{genesis do %s -- curl /v2/service_instances -X POST -d '{...}'}\n",
		$env->name, $env->name, $env->name, $env->name
	);
	
	unless ($self->validate_required_args(1, $usage_msg)) {
		return $self->done(0);
	}

	# Get connection details using mixin method
	my $connection_info = $self->get_blacksmith_connection_info();
	
	# Get the path from args
	my $path = shift @{$self->{args}};
	
	# Ensure path starts with /
	$path = "/$path" unless $path =~ m{^/};
	
	info("Executing curl request to #C{%s%s}...\n", $connection_info->{url}, $path);
	
	# Execute curl with authentication
	my ($out, $rc, $err) = run(
		{interactive => 1},
		'curl -u "$1:$2" "$3$4" "$@"',
		$connection_info->{username}, 
		$connection_info->{password}, 
		$connection_info->{url}, 
		$path,
		@{$self->{args}}
	);
	
	if ($rc != 0) {
		error("\nCurl request failed: %s\n", $err || 'Unknown error');
		return $self->done(0);
	}

	return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1: