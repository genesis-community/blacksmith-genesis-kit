# Blacksmith Addon Mixin
# This file provides common methods for Blacksmith addon hooks
# Include with: do dirname(__FILE__) . '/_addon.pm';
#
# Note: This file relies on the importing module to have the necessary
# 'use' statements for Genesis, Genesis::UI, etc.

# Include common utilities
use File::Basename qw/dirname/;
do(dirname(__FILE__) . '/_util.pm');

# Override init to add version check
sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

# Common method to get Blacksmith connection information
sub get_blacksmith_connection_info {
	my ($self) = @_;
	my $env = $self->env;
	
	# Set up connection details
	my $vault = $env->secrets_base;
	my $ip = $self->_get_blacksmith_ip();
	my $fqdn = $env->lookup('params.fqdn', '');
	my $host = $fqdn || $ip;

	my ($port, $scheme);
	if ($self->want_feature('broker-tls')) {
		$port = $env->lookup('params.blacksmith_tls_port', 443);
		$scheme = 'https';
	} else {
		$port = $env->lookup('params.blacksmith_port', 3000);
		$scheme = 'http';
	}

	my $blacksmith_username = 'blacksmith';
	
	# Get password from vault
	my $blacksmith_password;
	eval {
		$blacksmith_password = $self->vault->get("${vault}broker:password");
	};
	if ($@) {
		bail("Failed to retrieve Blacksmith password from vault: %s", $@);
	}
	
	return {
		url => "$scheme://$host:$port",
		username => $blacksmith_username,
		password => $blacksmith_password,
		scheme => $scheme,
		host => $host,
		port => $port
	};
}

# Common method to check if a command is available
sub check_command_availability {
	my ($self, $command, $install_hints) = @_;
	
	my ($cmd_check, $cmd_rc) = run({stderr => 0}, 'command -v $1 >/dev/null 2>&1', $command);
	if ($cmd_rc != 0) {
		error("\n#R{Error:} The '%s' command is not installed.\n", $command);
		error("Please install %s to use this addon.\n", $command);
		
		if ($install_hints) {
			for my $hint (@$install_hints) {
				error("  - %s: #G{%s}\n", $hint->{os}, $hint->{cmd});
			}
		}
		return 0;
	}
	
	return 1;
}

# Common method to get Blacksmith BOSH environment info
sub get_blacksmith_bosh_info {
	my ($self) = @_;
	my $env = $self->env;
	
	# Get exodus data for BOSH connection
	my $exodus = $self->exodus_data();
	
	return {
		alias => "$ENV{GENESIS_ENVIRONMENT}-blacksmith",
		environment => $exodus->{bosh_url} || $env->lookup('params.bosh_url'),
		client => $exodus->{bosh_client} || 'blacksmith',
		client_secret => $exodus->{bosh_client_secret}
	};
}

# Common method to get Cloud Foundry connection info (for CF integrations)
sub get_cf_connection_info {
	my ($self) = @_;
	my $env = $self->env;
	
	my $cf_env = $env->lookup('params.cf_environment');
	my $cf_deployment_type = $env->lookup('params.cf_deployment_type', 'cf');
	
	unless ($cf_env) {
		bail("CF environment not configured. Set params.cf_environment in your environment file.");
	}
	
	# Get CF credentials from the CF deployment's exodus data
	my $cf_exodus_path = "${cf_env}/${cf_deployment_type}";
	my $system_domain = $env->exodus_lookup('system_domain', undef, $cf_exodus_path);
	my $username = $env->exodus_lookup('admin_username', undef, $cf_exodus_path);
	my $password = $env->exodus_lookup('admin_password', undef, $cf_exodus_path);
	
	unless ($system_domain && $username && $password) {
		bail("CF deployment exodus data incomplete. Ensure CF deployment has completed successfully.");
	}
	
	return {
		api_url => "https://api.$system_domain",
		username => $username,
		password => $password,
		system_domain => $system_domain
	};
}

# Common method to validate addon arguments
sub validate_required_args {
	my ($self, $min_args, $usage_msg) = @_;
	
	my $args_count = scalar(@{$self->{args}});
	if ($args_count < $min_args) {
		error("\n#R{Error:} Insufficient arguments provided.\n\n");
		if ($usage_msg) {
			info("#Bu{Usage:}\n");
			info("%s\n", $usage_msg);
		}
		return 0;
	}
	
	return 1;
}

# Common method to display addon info
sub display_connection_info {
	my ($self, $info, $title) = @_;
	
	$title ||= "Connection Information";
	
	info("#Bu{%s:}\n", $title);
	info("  URL:      #C{%s}\n", $info->{url}) if $info->{url};
	info("  Host:     #C{%s}\n", $info->{host}) if $info->{host};
	info("  Port:     #C{%s}\n", $info->{port}) if $info->{port};
	info("  Scheme:   #C{%s}\n", $info->{scheme}) if $info->{scheme};
	info("  Username: #M{%s}\n", $info->{username}) if $info->{username};
	info("  Password: #Y{%s}\n", $info->{password}) if $info->{password};
	info("\n");
}

1;