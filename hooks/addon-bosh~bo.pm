#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Addon::Blacksmith::Bosh v4.0.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20
use Genesis qw/bail info run/;
use parent qw(Genesis::Hook::Addon);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub cmd_details {
  return
    "Sets up a local alias for the Blacksmith BOSH director and logs in.\n".
    "This is useful for troubleshooting service provisioning.";
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Set up connection details
  my $alias = "$ENV{GENESIS_ENVIRONMENT}-blacksmith";

  # Check if we already have the alias
  my ($has_alias, $alias_rc) = run('bosh envs | grep -q "^${BOSH_ENVIRONMENT}\\t${alias}\\t"');
  if ($alias_rc != 0) {
    # Set up alias if needed
    my ($setup_out, $setup_rc) = run('bosh alias-env --tty $1 | grep -v \'^User\'', $alias);
    bail("Failed to set up BOSH alias: %s", $setup_out) if $setup_rc != 0;
  }

  # Log in to BOSH
  my ($login_out, $login_rc) = run(
    'bosh logout >/dev/null 2>&1 && printf "%s\\n%s\\n" "$1" "$2" | BOSH_CLIENT="" BOSH_CLIENT_SECRET="" bosh login',
    $ENV{BOSH_CLIENT}, $ENV{BOSH_CLIENT_SECRET}
  );
  bail("Failed to log in to BOSH: %s", $login_out) if $login_rc != 0;

  return $self->done();
}

1;
