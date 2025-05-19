#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Blueprint::Blacksmith v4.0.0;

use strict;
use warnings;
use v5.20;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::Blueprint);

use Genesis qw/bail/;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->{files} = [];
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub perform {
  my ($blueprint) = @_; # $blueprint is '$self'

  $blueprint->add_files(qw(
    manifests/blacksmith/blacksmith.yml
    manifests/releases/blacksmith.yml
  ));

  # IaaS feature check
  my $iaas = 0;
  my $external_bosh = 0;
  my $forges = 0;

  for my $feature ($blueprint->features) {
    if ($feature eq 'ocfp') {
      $external_bosh += 1; # OCFP Ref Arch requires external bosh
    }
    elsif ($feature eq 'external-bosh') {
      $blueprint->add_files("manifests/blacksmith/external-bosh.yml");
      $external_bosh += 1;
    }
    elsif ($feature =~ /^(aws|azure|google|openstack|vsphere|stackit)$/) {
      $ENV{OCFP_IAAS} = $feature;
      $iaas += 1;
    }
    elsif ($feature eq 'broker-tls') {
      $blueprint->add_files("manifests/blacksmith/broker-tls.yml");
    }
    elsif ($feature eq 'shield-backups') {
      $blueprint->add_files("manifests/blacksmith/shield-backups.yml");
    }
    elsif ($feature eq 'shield-agent') {
      $blueprint->add_files(
        "manifests/blacksmith/shield-agent.yml",
        "manifests/releases/shield-agent.yml"
      );
    }
    elsif ($feature =~ /^(rabbitmq|redis|postgresql|mariadb|kubernetes)$/) {
      $forges += 1;
      $blueprint->add_files("manifests/forges/$feature.yml");
    }
    elsif ($feature eq 'redis-tls') {
      $blueprint->add_files("manifests/forges/redis-tls.yml");
    }
    elsif ($feature eq 'redis-dual-mode') {
      $blueprint->add_files("manifests/forges/redis-dual-mode.yml");
    }
    elsif ($feature eq 'rabbitmq-tls') {
      $blueprint->add_files("manifests/forges/rabbitmq-tls.yml");
    }
    elsif ($feature eq 'rabbitmq-dual-mode') {
      $blueprint->add_files("manifests/forges/rabbitmq-dual-mode.yml");
    }
    elsif ($feature eq 'rabbitmq-dashboard-registration') {
      $blueprint->add_files("manifests/forges/rabbitmq-dashboard-registration.yml");
    }
    elsif ($feature eq 'cf-route-registrar') {
      $blueprint->add_files("manifests/blacksmith/cf-route-registrar.yml");
    }
    elsif (-f $blueprint->env->path("ops/$feature.yml")) {
      $blueprint->add_files("ops/$feature.yml");
    }
  }

  if ($external_bosh == 0) {
    $blueprint->add_files("manifests/blacksmith/bosh.yml");
  }

  # Add the IaaS manifest only if we are not using the OCFP feature.
  if (!$blueprint->want_feature("ocfp") && $iaas != 0) {
    $blueprint->add_files("manifests/iaas/$ENV{OCFP_IAAS}.yml");

    if (!$blueprint->want_feature("vsphere")) {
      # vSphere doesn't need a registry, but everyone else does...
      $blueprint->add_files("manifests/addons/registry.yml");
    }
  }

  if ($blueprint->want_feature("rabbitmq-autoscale")) {
    $blueprint->add_files("manifests/forges/rabbitmq-autoscale.yml");
  }

  if ($blueprint->want_feature("ocfp")) {
    $blueprint->add_files(
      "ocfp/meta.yml",
      "ocfp/ocfp.yml",
      "ocfp/$ENV{OCFP_IAAS}/ocf.yml"
    );

    if ($blueprint->want_feature("shield-backups")) {
      $blueprint->add_files("ocfp/shield-backups.yml");
    }

    if ($blueprint->want_feature("shield-agent")) {
      $blueprint->add_files("ocfp/shield-agent.yml");
    }
  }

  # Sanity Check Time!
  # If we haven't chosen an IaaS, that's a problem.
  if ($iaas == 0 && $external_bosh == 0) {
    bail("You have not enabled an IaaS feature flag.");
  }

  # If we have chosen more than one IaaS, that's a problem.
  if ($iaas > 1) {
    bail("You have enabled more than one IaaS feature flag.");
  }

  # If we didn't activate at least one Forge, that's a problem.
  if ($forges == 0) {
    bail("You have not activated any Blacksmith Forges.");
  }

  return $blueprint->done();
}

1;

