#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 et:
package Genesis::Hook::Check::Blacksmith v4.0.0;

use strict;
use warnings;
use v5.20; # Genesis supports min perl v5.20.

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

# Parent class inheritance
use parent qw(Genesis::Hook);

# Import required functions
use Genesis qw/bail info run/;

sub init {
  my ($class, %ops) = @_;
  my $obj = $class->SUPER::init(%ops);
  $obj->{ok} = 1; # Start assuming all checks will pass
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;
  my $ok = 1;

  # Environment Parameter checks
  if ($self->want_feature('vsphere')) {
    for my $e ('ephemeral', 'persistent') {
      my $t = $env->lookup("params.vsphere_${e}_datastores");
      if (!$t || ref($t) ne "ARRAY") {
        $env->notify(error => "${e} vsphere datastores is not a list [#R{FAILED}]");
        $ok = 0;
      } else {
        $env->notify(info => "${e} vsphere datastores checks out [#G{OK}]");
      }
    }
  }

  my $ip = $env->lookup('params.ip');
  $env->notify(info => "checking if our certificates match the director static ip ($ip)...");

  my $vault = "$ENV{GENESIS_SECRETS_MOUNT}/$ENV{GENESIS_VAULT_PREFIX}";
  for my $cert (
    'tls/director',
    'tls/nats/server'
  ) {
    if (!$self->vault->exists("$vault/$cert")) {
      info("    - $vault/$cert [#Y{MISSING}]");
    } else {
      my ($out, $rc) = run({stderr => '/dev/null'}, 'safe --quiet x509 validate "$1" --for "$2"', "$vault/$cert", "$ip");
      if ($rc == 0) {
        info("    - $vault/$cert [#G{OK}]");
      } else {
        info("    - $vault/$cert [#R{INVALID}]");
        my ($validation_out, $valid_rc) = run('safe x509 validate "$1" --for "$2" 2>&1', "$vault/$cert", "$ip");
        info("      %s", $validation_out);
        $ok = 0;
      }
    }
  }

  if ($ok) {
    $env->notify(success => "environment files [#G{OK}]");
  } else {
    $env->notify(error => "environment files [#R{FAILED}]");
  }

  return $self->done();
}

1;

