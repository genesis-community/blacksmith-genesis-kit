#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Addon::Blacksmith::Boss v4.0.0;

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
    "Interacts with the Blacksmith broker via the 'boss' CLI.\n".
    "The boss CLI must be installed separately.\n".
    "See https://github.com/blacksmith-community/boss for details.";
}

sub perform {
  my ($self) = @_;

  # Check if boss is installed
  my ($boss_check, $boss_rc) = run({stderr => '/dev/null'}, 'command -v boss >/dev/null 2>&1');
  if ($boss_rc != 0) {
    info("  !!! install the 'boss' cli first!");
    info("      (https://github.com/blacksmith-community/boss)");
    return $self->done(0);
  }

  # Execute boss with all provided arguments
  my ($out, $rc, $err) = run({interactive => 1}, 'boss "$@"', @{$self->{args}});
  bail("Failed to run boss command: %s", $err) if $rc != 0;

  return $self->done(1);
}

1;
