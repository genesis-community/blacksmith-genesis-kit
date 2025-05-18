#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Addon::Blacksmith::Register v4.0.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20
use Genesis qw/bail info run new_enough/;
use parent qw(Genesis::Hook::Addon);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";
use File::Temp qw/tempdir/;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub cmd_details {
  return
    "Registers this Blacksmith Broker with a Genesis-deployed Cloud Foundry.\n".
    "Also runs CA synchronization to ensure certificates are properly set up.\n".
    "Usage: register [cf-environment-name]\n".
    "If no CF environment name is provided, the current environment name is used.";
}

# Helper method to sync CA certificates
sub ca_sync {
  my ($self) = @_;

  info("Fetching Blacksmith CA certificate details...");
  info("Setting values in credhub for blacksmith_services_ca...");

  my $path = "$ENV{GENESIS_SECRETS_MOUNT}/$ENV{GENESIS_VAULT_PREFIX}/broker/ca";

  my ($out, $rc, $err) = run(
    'genesis credhub $1 set -t certificate -n "/$1-bosh/$1-blacksmith/blacksmith_services_ca" '.
    '-c <(safe get "$2:certificate") -p <(safe get "$2:key")',
    $ENV{GENESIS_ENVIRONMENT}, $path
  );
  bail("Failed to set CA certificate in credhub: %s", $err) if $rc != 0;

  info("Setting values in credhub for nats_client_cert...");

  my $path_1 = "$ENV{GENESIS_SECRETS_MOUNT}exodus/$ENV{GENESIS_ENVIRONMENT}/cf";
  my $cf_path = "$ENV{GENESIS_SECRETS_MOUNT}/$ENV{GENESIS_VAULT_PREFIX}" =~ s/blacksmith/cf/r;

  ($out, $rc, $err) = run(
    'genesis credhub $1 set -t certificate -n "/$1-bosh/$1-cf/nats_client_cert" '.
    '-c <(safe get "$2:nats_client_cert") -p <(safe get "$2:nats_client_key") '.
    '-r <(safe get "$3/nats_ca:certificate")',
    $ENV{GENESIS_ENVIRONMENT}, $path_1, $cf_path
  );
  bail("Failed to set NATS client certificate in credhub: %s", $err) if $rc != 0;

  return 1;
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Sync CA certificates first
  $self->ca_sync();

  # Get CF environment name
  my $cf_env = $self->{args}[0] || $ENV{GENESIS_ENVIRONMENT};

  # Set up connection details
  my $vault = "$ENV{GENESIS_SECRETS_MOUNT}/$ENV{GENESIS_VAULT_PREFIX}";
  my $ip = $env->lookup('params.ip');
  my $fqdn = $env->lookup('params.fqdn');
  my $host = $fqdn ? $fqdn : $ip;

  my ($port, $scheme);
  if ($self->want_feature('broker-tls')) {
    $port = $env->lookup('params.blacksmith_tls_port', 443);
    $scheme = 'https';
  } else {
    $port = $env->lookup('params.blacksmith_port', 3000);
    $scheme = 'http';
  }

  my $blacksmith_url = "$scheme://$host:$port";
  my $blacksmith_username = 'blacksmith';
  my $blacksmith_password = $self->vault->get("$vault/broker:password");

  # Get CF API and credentials
  my $cf_version = $env->exodus_lookup("kit_version", undef, "$cf_env/cf");

  my $cf_api;
  if ($cf_version && new_enough($cf_version, "2.0.0-rc1")) {
    $cf_api = "https://" . $env->exodus_lookup("api_domain", undef, "$cf_env/cf");
  } else {
    $cf_api = $env->exodus_lookup("api_url", undef, "$cf_env/cf");
  }

  my $cf_user = $env->exodus_lookup("admin_username", undef, "$cf_env/cf");
  my $cf_pass = $env->exodus_lookup("admin_password", undef, "$cf_env/cf");

  # Create temporary home directory for CF CLI
  my $tempdir = tempdir("blacksmith.regXXXXXXX", CLEANUP => 1);
  local $ENV{HOME} = $tempdir;

  # Connect to CF API
  info("authenticating to #C{%s} as #G{%s}...", $cf_api, $cf_user);
  my ($api_out, $api_rc) = run('cf api "$1" --skip-ssl-validation', $cf_api);
  bail("Failed to target CF API: %s", $api_out) if $api_rc != 0;

  my ($auth_out, $auth_rc) = run('cf auth "$1" "$2"', $cf_user, $cf_pass);
  bail("Failed to authenticate to CF: %s", $auth_out) if $auth_rc != 0;

  # Check if service broker already exists
  my ($exists_out, $exists_rc) = run(
    'cf curl /v2/service_brokers|jq --arg env_name "$1-blacksmith" -r \'.resources[].entity | select(.name==$env_name) | .name\'',
    $cf_env
  );

  if ($exists_out =~ /\S/) {
    info("Found and updating service broker #M{%s-blacksmith}...", $cf_env);
    my ($update_out, $update_rc) = run(
      'cf update-service-broker "$1-blacksmith" "$2" "$3" "$4"',
      $cf_env, $blacksmith_username, $blacksmith_password, $blacksmith_url
    );
    bail("Failed to update service broker: %s", $update_out) if $update_rc != 0;
  } else {
    info("creating service broker #M{%s-blacksmith}...", $cf_env);
    my ($create_out, $create_rc) = run(
      'cf create-service-broker "$1-blacksmith" "$2" "$3" "$4"',
      $cf_env, $blacksmith_username, $blacksmith_password, $blacksmith_url
    );
    bail("Failed to create service broker: %s", $create_out) if $create_rc != 0;
  }

  # Enable service access for all services
  info("enabling service access...");
  my ($services_out, $services_rc) = run(
    'curl -Lsk -u "$1:$2" "$3/v2/catalog" -H Accept:application/json | jq -r \'.services[].id\'',
    $blacksmith_username, $blacksmith_password, $blacksmith_url
  );
  bail("Failed to retrieve service catalog: %s", $services_out) if $services_rc != 0;

  my @service_ids = split(/\s+/, $services_out);
  foreach my $service_id (@service_ids) {
    next unless $service_id =~ /\S/;
    info("Enabling service access for #C{%s}", $service_id);
    my ($enable_out, $enable_rc) = run('cf enable-service-access "$1"', $service_id);
    bail("Failed to enable service access for %s: %s", $service_id, $enable_out) if $enable_rc != 0;
  }

  return $self->done(1);
}

1;
