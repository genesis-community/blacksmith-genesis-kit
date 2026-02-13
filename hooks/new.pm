package Genesis::Hook::New::Blacksmith v1.1.0;

use strict;
use warnings;
use v5.20; # Genesis supports min perl v5.20.

BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

# Parent class inheritance
use parent qw(Genesis::Hook);

# Import required functions
use Genesis qw/trace bug bail warning info/;
use Data::Dumper;
use File::Basename qw/basename dirname/;
use File::Path qw/mkpath/;

sub init {
  my ($class, %ops) = @_;
  my $obj = $class->SUPER::init(%ops);
	$obj->{files} = [];
	$obj->check_minimum_genesis_version('3.1.0');
  $obj->{features} = [];
  $obj->{config} = {
    kit => {
      name => $ENV{GENESIS_KIT_NAME},
      version => $ENV{GENESIS_KIT_VERSION},
      features => []
    },
    params => {}
  };
  return $obj;
}

sub perform {
  my ($self) = @_;

  return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
