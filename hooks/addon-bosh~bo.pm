package Genesis::Hook::Addon::Blacksmith::BOSH v1.3.0;

use v5.20;
use warnings;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . '/.genesis/lib' }

use parent qw(Genesis::Hook::Addon);

use Genesis qw/bail info warning error/;

# Include common methods from mixin
BEGIN {
	require File::Basename;
	my $mixin_file = File::Basename::dirname(__FILE__) . '/_addon.pm';
	do $mixin_file or die "Failed to include addon mixin $mixin_file: $!";
}

sub cmd_details {
	return
		"Prints shell export lines (BOSH_ENVIRONMENT, BOSH_CA_CERT, BOSH_CLIENT,\n".
		"and BOSH_CLIENT_SECRET) for the Blacksmith BOSH director, so that the\n".
		"bosh CLI can reach it when the broker is not answering. The output\n".
		"holds a secret. Use it as: eval \"\$(genesis do <env> bosh)\"";
}

# Quote a value for the shell, escaping any embedded single quote.
sub _shell_quote {
	my ($value) = @_;
	$value =~ s/'/'\\''/g;
	return "'$value'";
}

sub perform {
	my ($self) = @_;
	my $env_name = $self->env->name;
	my $bosh_info = $self->get_blacksmith_bosh_info();

	print STDOUT join("\n",
		"export BOSH_ENVIRONMENT="   . _shell_quote($bosh_info->{environment}),
		"export BOSH_CA_CERT="       . _shell_quote($bosh_info->{ca_cert}),
		"export BOSH_CLIENT="        . _shell_quote($bosh_info->{client}),
		"export BOSH_CLIENT_SECRET=" . _shell_quote($bosh_info->{client_secret}),
	), "\n";

	print STDERR "Note: the output above holds a secret. The usual use is: ".
		"eval \"\$(genesis do $env_name bosh)\"\n";

	return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
