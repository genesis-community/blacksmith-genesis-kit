#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::PreDeploy::Blacksmith v4.0.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20
use Genesis qw/bail info run/;
use parent qw(Genesis::Hook);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";

sub init {
  my ($class, %ops) = @_;
  my $obj = $class->SUPER::init(%ops);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Only process shield backups if feature is enabled
  if ($self->want_feature('shield-backups')) {
    # Ensure shield CLI is available
    my ($shield_check, $shield_rc) = run({stderr => '/dev/null'}, 'command -v shield >/dev/null 2>&1');
    if ($shield_rc != 0) {
      bail('error: shield is not installed.');
    }

    # Get shield configuration
    my $shield_admin_username = $env->lookup('meta.shield.admin_username');
    my $shield_admin_password = $env->lookup('meta.shield.admin_password');
    my $shield_address = $env->lookup('meta.shield.address');

    my $blacksmith_shield_username = $env->lookup('params.shield_username');
    my $blacksmith_shield_password = $env->lookup('params.shield_password');
    my $blacksmith_shield_tenant = $env->lookup('params.shield_tenant');

    # Set up shield environment
    $ENV{BLACKSMITH_SHIELD_USERNAME} = $blacksmith_shield_username;
    $ENV{BLACKSMITH_SHIELD_PASSWORD} = $blacksmith_shield_password;
    $ENV{BLACKSMITH_SHIELD_TENANT} = $blacksmith_shield_tenant;

    # Connect to shield and import configuration
    my ($api_out, $api_rc) = run('shield api $1 blacksmith-shield -k', $shield_address);
    bail("Failed to connect to shield API: %s", $api_out) if $api_rc != 0;

    my ($login_out, $login_rc) = run(
      'shield login -c blacksmith-shield --username $1 --password $2',
      $shield_admin_username, $shield_admin_password
    );
    bail("Failed to log in to shield: %s", $login_out) if $login_rc != 0;

    my ($import_out, $import_rc) = run(
      'shield import -c blacksmith-shield <(spruce merge manifests/templates/shield-backups-import.yml)'
    );
    bail("Failed to import shield configuration: %s", $import_out) if $import_rc != 0;
  }

  # Return successful completion
  return $self->done(1);
}

1;
