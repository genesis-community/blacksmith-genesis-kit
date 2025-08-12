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

  if ($self->want_feature('ocfp')) {
    my $vault_path = $env->secrets_base."ocf/net/subnets/ocfp-1/reserved-ips";
    if ($env->vault->has($vault_path, "blacksmith_ip")) {
      my $ip = $env->vault->get($vault_path, "blacksmith_ip");
      return $ip;
    } else {
      bail(
        "\nCould not retrieve Blacksmith IP from OCFP vault path:\n".
        " $vault_path:blacksmith_ip! \n".
        " Ensure it is set and then retry.\n"
      );
    }
  }
  # Default: get IP from params
  return $env->lookup('params.ip', '');
}

1;
