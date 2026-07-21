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
    my $vault_path = $env->ocfp_config_base."/net/subnets/ocfp-1/reserved-ips";
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

# _needs_blacksmith_ca_sync - Whether the blacksmith_services_ca needs to be
# synchronized into this deployment's config server. Any feature that signs
# a service certificate from broker/ca requires the CA to be resolvable via
# the cross-deployment credhub variable path service manifests reference.
sub _needs_blacksmith_ca_sync {
  my ($self) = @_;

  return 1 if $self->want_feature('broker-tls');
  return 1 if $self->want_feature('rabbitmq-tls');
  return 1 if $self->want_feature('redis-tls');
  return 1 if $self->want_feature('valkey-tls');

  return 0;
}

# _sync_blacksmith_services_ca - Seeds the blacksmith_services_ca CA into
# this deployment's config server (credhub), sourced from the vault-managed
# broker/ca. Forge service deployments reference this CA cross-deployment
# (by this deployment's name) when signing their own leaf certificates;
# without it having been seeded here first, BOSH's config server returns a
# 404 the first time a service instance is provisioned. Safe to call
# repeatedly; genesis credhub set is idempotent.
sub _sync_blacksmith_services_ca {
  my ($self) = @_;
  my $env = $self->env;

  my $broker_ca_path = $env->secrets_base . 'broker/ca';

  info("Checking if Blacksmith Services CA exists: $broker_ca_path\n");
  unless ($self->env->vault->has($broker_ca_path)) {
    warning("  Blacksmith broker CA not found at: $broker_ca_path\n");
    warning("  Skipping CA synchronization.\n");
    return 1;
  }

  info("  Setting blacksmith_services_ca in Credhub...\n");
  my ($out, $rc, $err) = run(
    {stderr => 0},
    'genesis credhub $1 set -t certificate -n "/$1-bosh/$1-blacksmith/blacksmith_services_ca" '.
    '-c <(safe get "$2:certificate") -p <(safe get "$2:key")',
    $env->name, $broker_ca_path
  );

  if ($rc != 0) {
    error("  Failed to set CA certificate in Credhub: %s\n", $err || 'Unknown error');
    return 0;
  }
  info("  ✓ Blacksmith services CA synchronized\n");

  return 1;
}

1;
