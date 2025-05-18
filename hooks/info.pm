#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 et:
package Genesis::Hook::Info::Blacksmith v4.0.0;

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
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;
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

  my $bosh_environment = $env->exodus_lookup('bosh_address');
  my $bosh_ca_cert = $env->exodus_lookup('bosh_cacert');
  my $bosh_client = $env->exodus_lookup('bosh_username');
  my $bosh_client_secret = $env->exodus_lookup('bosh_password');

  info("\nbosh env");
  my ($out, $rc, $err) = run("bosh -A env --tty | sed -e 's/^/  /'");
  bail("Failed to execute bosh env command: %s", $err) if $rc;
  info($out);

  info("\n\nblacksmith (internal) bosh director");
  info("\tbosh url: #C{%s}", $bosh_environment);
  info("\tusername: #M{%s}", $bosh_client);
  info("\tpassword: #G{%s}", $bosh_client_secret);

  info("\n\nblacksmith web management UI");
  info("\tweb url:   #C{%s}", $blacksmith_url);
  info("\tusername:  #M{%s}", $blacksmith_username);
  info("\tpassword:  #G{%s}", $blacksmith_password);
  info("\tclickable: #B{%s://%s:%s@%s:%s}", $scheme, $blacksmith_username, $blacksmith_password, $host, $port);

  if ($self->want_feature('shield-backups')) {
    my $shield_url = $env->exodus_lookup('shield_url');
    my $shield_username = $env->exodus_lookup('shield_username');
    my $shield_password = $env->exodus_lookup('shield_password');

    info("\n\nshield");
    info("\turl:       #C{%s}", $shield_url);
    info("\tusername:  #M{%s}", $shield_username);
    info("\tpassword:  #G{%s}", $shield_password);
  }

  info("\n\nblacksmith catalog");

  my ($boss_out, $boss_rc) = run({stderr => 0}, 'command -v boss >/dev/null 2>&1');
  if ($boss_rc != 0) {
    info("  !!! install the 'boss' cli to query the blacksmith catalog");
    info("      (https://github.com/jhunt/boss)");
  } else {
    my ($catalog, $catalog_rc, $catalog_err) = run('boss catalog | sed -e \'s/^/  /\'');
    bail("Failed to execute boss catalog command: %s", $catalog_err) if $catalog_rc;
    info($catalog);
  }

  return $self->done(1);
}

1;

