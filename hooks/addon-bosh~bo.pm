package Genesis::Hook::Addon::Blacksmith::BOSH v1.2.0;

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
		"Sets up a local alias for the Blacksmith BOSH director and logs in.\n".
		"This is useful for troubleshooting service provisioning.";
}

sub perform {
	my ($self) = @_;
	my $env = $self->env;

	# Get BOSH connection details using mixin method
	my $bosh_info = $self->get_blacksmith_bosh_info();
	
	# Set up connection details
	my $alias = $bosh_info->{alias};

	# Check if we already have the alias
	my ($has_alias, $alias_rc) = run('bosh envs | grep -q "^${BOSH_ENVIRONMENT}\t${alias}\t"');
	if ($alias_rc != 0) {
		# Set up alias if needed
		info("Setting up BOSH alias #C{%s}...\n", $alias);
		my ($setup_out, $setup_rc) = run('bosh alias-env --tty $1 | grep -v \'^User\'', $alias);
		bail("Failed to set up BOSH alias: %s", $setup_out) if $setup_rc != 0;
	}

	# Log in to BOSH
	info("Logging in to BOSH director...\n");
	my ($login_out, $login_rc) = run(
		'bosh logout >/dev/null 2>&1 && printf "%s\\n%s\\n" "$1" "$2" | BOSH_CLIENT="" BOSH_CLIENT_SECRET="" bosh login',
		$bosh_info->{client}, $bosh_info->{client_secret}
	);
	bail("Failed to log in to BOSH: %s", $login_out) if $login_rc != 0;

	info("\n#G{✓} Successfully connected to Blacksmith BOSH director.\n");
	info("Alias: #C{%s}\n", $alias);
	info("\nYou can now use standard BOSH commands with this director.\n");
	
	return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1: