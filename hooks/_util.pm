# Blacksmith Utilities Mixin
# This file provides common utility methods for Blacksmith hooks
# Include with: do dirname(__FILE__) . '/_util.pm';
#
# Note: This file relies on the importing module to have the necessary
# 'use' statements for Genesis, Genesis::UI, etc.

# Helper to get Blacksmith IP based on deployment type
sub _get_blacksmith_ip {
	my ($self) = @_;
	my $env = $self->env;
	
	# For OCFP deployments, get IP from vault
	if ($self->want_feature('ocfp')) {
		my $ocfp_env = $env->lookup('params.ocfp_env', '');
		if ($ocfp_env) {
			# Construct the vault path for OCFP reserved IPs
			my $vault_path = "/ocf/net/subnets/ocfp-1/reserved-ips";
			my $ip_key = "blacksmith_ip";
			
			# Try to get the IP from vault
			my $vault_client = $self->vault;
			if ($vault_client && $vault_client->exists($vault_path)) {
				my $data = $vault_client->get($vault_path);
				if ($data && $data->{$ip_key}) {
					return $data->{$ip_key};
				}
			}
			
			# Fall back to params.ip if vault lookup fails
			warning("Could not retrieve Blacksmith IP from OCFP vault path $vault_path:$ip_key, falling back to params.ip");
		}
	}
	
	# Default: get IP from params
	return $env->lookup('params.ip', '');
}

1;